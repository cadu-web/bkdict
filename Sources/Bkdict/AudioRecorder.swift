import AVFoundation

/// Captures the chosen microphone (see Microphones) as 16 kHz mono, which is what Whisper expects.
///
/// Uses a capture session, which opens one specific device and converts to the format we ask for. AVAudioEngine,
/// used before, keeps the previous device's format after a microphone switch: the tap then fails, or raises an
/// exception that kills the app (AirPods at 24 kHz against a 48 kHz built-in microphone).
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Failure: LocalizedError {
        case noMicrophone

        var errorDescription: String? { "Microfone indisponível" }
    }

    static let sampleRate: Double = 16_000

    var onLevel: (Float) -> Void = { _ in }
    /// Every chunk as it arrives, for recordings written straight to disk (meetings).
    var onSamples: (([Float]) -> Void)?
    /// Off for long recordings that stream through `onSamples` instead of piling up in memory.
    var keepsSamples = true

    private var session: AVCaptureSession?
    /// Delivers the buffers in order; `stop()` drains it so the last words are not cut.
    private let queue = DispatchQueue(label: "co.bkdg.bkdict.recorder")
    private var samples: [Float] = []
    private let lock = NSLock()

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        // Core Audio's device UID is the capture device's uniqueID.
        let chosen = Microphones.resolve(Settings.microphone).flatMap { AVCaptureDevice(uniqueID: $0.uid) }
        guard let device = chosen ?? AVCaptureDevice.default(for: .audio) else { throw Failure.noMicrophone }

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw Failure.noMicrophone }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        self.session = session
    }

    /// Stops capture and returns the recorded samples.
    func stop() -> [Float] {
        session?.stopRunning()
        session = nil
        queue.sync {}
        return lock.withLock { samples }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                          dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { return }
        let count = length / MemoryLayout<Float>.size
        let chunk = pointer.withMemoryRebound(to: Float.self, capacity: count) { Array(UnsafeBufferPointer(start: $0, count: count)) }
        if keepsSamples { lock.withLock { samples.append(contentsOf: chunk) } }
        onSamples?(chunk)

        let power = chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1))
        onLevel(sqrt(power))
    }

    /// Encodes samples as a 16-bit PCM mono WAV file.
    static func wavData(from samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
