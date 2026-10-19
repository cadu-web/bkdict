import AppKit
import Foundation

/// A recorded meeting, stored as `meeting.json` next to its two audio tracks (see docs/reunioes.md).
struct Meeting: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case recording, transcribing, separating, summarizing, ready, failed }

    struct Segment: Codable, Hashable {
        enum Source: String, Codable { case me, them }
        var source: Source
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        /// The voice, for "Eles" segments once the track was split by voice (phase 3).
        var speaker: Int?
    }

    let id: String
    var title: String
    let startedAt: Date
    var duration: TimeInterval = 0
    /// The call app it was recorded from, when the Bkdict noticed the call (phase 2).
    var app: String?
    var systemAudio = true
    var status = Status.recording
    var progress = 0.0
    var error: String?
    var segments: [Segment] = []
    /// A name per voice; "" keeps the default "Pessoa N". Optional so meetings saved before phase 3 still load.
    var speakers: [String]?
    var summary: String?

    var folder: URL { MeetingCenter.directory.appendingPathComponent(id, isDirectory: true) }
    var micURL: URL { folder.appendingPathComponent("mic.wav") }
    var systemURL: URL { folder.appendingPathComponent("system.wav") }

    /// `[mm:ss] Você: …`, one line per segment; the format the summary reads and "Copiar transcrição" copies.
    var transcript: String {
        segments.map { "[\(Self.clock($0.start))] \(label(for: $0)): \($0.text)" }.joined(separator: "\n")
    }

    /// "Você", the voice's name, "Pessoa N", or "Eles" when the voices were not split.
    func label(for segment: Segment) -> String {
        guard segment.source == .them else { return "Você" }
        guard let speaker = segment.speaker else { return "Eles" }
        return name(of: speaker)
    }

    func name(of speaker: Int) -> String {
        let names = speakers ?? []
        let name = speaker < names.count ? names[speaker].trimmingCharacters(in: .whitespaces) : ""
        return name.isEmpty ? "Pessoa \(speaker + 1)" : name
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Records meetings and turns them into a transcript (Você / Eles) and a summary, all on this Mac.
@MainActor
final class MeetingCenter: ObservableObject {
    nonisolated static var directory: URL {
        let url = Settings.supportDirectory.appendingPathComponent("meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Published private(set) var meetings: [Meeting] = []
    /// When the meeting being recorded started; nil when not recording.
    @Published private(set) var recordingSince: Date?

    /// Set by AppController: the same transcription as dictation (engine, language, dictionary hint).
    var transcribe: (Data) async throws -> String = { _ in "" }
    /// Set by AppController: the Dictionary's corrections.
    var correct: (String) -> String = { $0 }

    private var recording: (meeting: Meeting, mic: AudioRecorder, micFile: WavFileWriter,
                            system: AnyObject?, systemFile: WavFileWriter)?
    private var processing: Set<String> = []

    init() {
        load()
    }

    // MARK: - Recording

    func start(app: String? = nil) {
        guard recording == nil else { return }
        let now = Date()
        let id = Self.idFormatter.string(from: now)
        let title = app.map { "\($0) · \(Self.titleFormatter.string(from: now))" } ?? "Reunião de \(Self.titleFormatter.string(from: now))"
        var meeting = Meeting(id: id, title: title, startedAt: now)
        meeting.app = app
        do {
            try FileManager.default.createDirectory(at: meeting.folder, withIntermediateDirectories: true)
            let micFile = try WavFileWriter(url: meeting.micURL)
            let systemFile = try WavFileWriter(url: meeting.systemURL)

            let mic = AudioRecorder()
            mic.keepsSamples = false
            mic.onSamples = { micFile.append($0) }
            try mic.start()

            var system: AnyObject?
            if #available(macOS 14.2, *) {
                let recorder = SystemAudioRecorder()
                recorder.onSamples = { systemFile.append($0) }
                do {
                    try recorder.start()
                    system = recorder
                } catch {
                    meeting.systemAudio = false
                    NSLog("Bkdict: \(error.localizedDescription)")
                }
            } else {
                meeting.systemAudio = false
            }
            recording = (meeting, mic, micFile, system, systemFile)
            recordingSince = now
            save(meeting)
        } catch {
            meeting.status = .failed
            meeting.error = "Não foi possível começar a gravar: \(error.localizedDescription)"
            save(meeting)
        }
    }

    func stop() {
        guard let current = recording else { return }
        recording = nil
        recordingSince = nil
        _ = current.mic.stop()
        if #available(macOS 14.2, *) { (current.system as? SystemAudioRecorder)?.stop() }
        current.micFile.close()
        current.systemFile.close()

        var meeting = current.meeting
        meeting.duration = max(current.micFile.duration, current.systemFile.duration)
        meeting.status = .transcribing
        save(meeting)
        process(meeting.id)
    }

    /// Stops a recording when the app quits; processing resumes on the next launch.
    func stopForQuit() {
        guard let current = recording else { return }
        recording = nil
        _ = current.mic.stop()
        if #available(macOS 14.2, *) { (current.system as? SystemAudioRecorder)?.stop() }
        current.micFile.close()
        current.systemFile.close()
        var meeting = current.meeting
        meeting.duration = max(current.micFile.duration, current.systemFile.duration)
        meeting.status = .transcribing
        save(meeting)
    }

    // MARK: - Library

    func delete(_ id: String) {
        guard recording?.meeting.id != id else { return }
        try? FileManager.default.removeItem(at: MeetingCenter.directory.appendingPathComponent(id))
        meetings.removeAll { $0.id == id }
    }

    func resummarize(_ id: String) {
        guard var meeting = meetings.first(where: { $0.id == id }), !processing.contains(id) else { return }
        meeting.status = .summarizing
        meeting.error = nil
        save(meeting)
        processing.insert(id)
        Task {
            var current = meeting
            await summarize(&current)
            processing.remove(id)
        }
    }

    private func load() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        meetings = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("meeting.json")) else { return nil }
            return try? Self.decoder.decode(Meeting.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
        // Picks up meetings interrupted by a quit or a crash.
        for meeting in meetings where meeting.status != .ready && meeting.status != .failed {
            WavFileWriter.repair(meeting.micURL)
            WavFileWriter.repair(meeting.systemURL)
            var updated = meeting
            if updated.status == .recording {
                updated.duration = Double((try? FileManager.default.attributesOfItem(atPath: meeting.micURL.path)[.size] as? Int) ?? 0) / 32_000
                updated.status = .transcribing
                save(updated)
            }
            process(updated.id)
        }
    }

    private func save(_ meeting: Meeting) {
        if let data = try? Self.encoder.encode(meeting) {
            try? data.write(to: meeting.folder.appendingPathComponent("meeting.json"), options: .atomic)
        }
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        } else {
            meetings.insert(meeting, at: 0)
        }
    }

    // MARK: - Processing

    private func process(_ id: String) {
        guard !processing.contains(id), let stored = meetings.first(where: { $0.id == id }) else { return }
        processing.insert(id)
        Task {
            var meeting = stored
            defer { processing.remove(id) }
            if meeting.status == .transcribing {
                do {
                    try await transcribeTracks(&meeting)
                } catch {
                    meeting.status = .failed
                    meeting.error = "Falha ao transcrever: \(error.localizedDescription)"
                    save(meeting)
                    return
                }
            }
            if meeting.status == .separating { await separate(&meeting) }
            await summarize(&meeting)
        }
    }

    private func transcribeTracks(_ meeting: inout Meeting) async throws {
        let mic = meeting.micURL, system = meeting.systemURL
        let (micParts, systemParts, systemSilent) = await Task.detached {
            (SpeechDetector.segments(in: mic), SpeechDetector.segments(in: system), SpeechDetector.isSilent(system))
        }.value
        // Permission denied or no 14.2: the tap delivers only silence.
        if systemSilent && !micParts.isEmpty { meeting.systemAudio = false }

        let parts = (micParts.map { (Meeting.Segment.Source.me, $0) } + systemParts.map { (.them, $0) })
            .sorted { $0.1.lowerBound < $1.1.lowerBound }
        var segments: [Meeting.Segment] = []
        for (index, (source, range)) in parts.enumerated() {
            let url = source == .me ? mic : system
            let samples = await Task.detached { WavFileWriter.samples(in: url, from: range.lowerBound, to: range.upperBound) }.value
            let text = try await transcribe(AudioRecorder.wavData(from: samples))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(.init(source: source, start: range.lowerBound, end: range.upperBound, text: correct(text)))
            }
            meeting.progress = Double(index + 1) / Double(parts.count)
            if index % 3 == 0 || index == parts.count - 1 { save(meeting) }
        }
        meeting.segments = SpeechDetector.removingEcho(segments)
        meeting.status = .separating
        meeting.progress = 1
        save(meeting)
    }

    /// Splits "Eles" by voice. A failure leaves the meeting with "Eles", as before phase 3.
    private func separate(_ meeting: inout Meeting) async {
        if meeting.segments.contains(where: { $0.source == .them }) {
            do {
                let turns = try await Diarizer.turns(in: meeting.systemURL)
                let (segments, voices) = Diarizer.assign(meeting.segments, turns: turns)
                meeting.segments = segments
                meeting.speakers = Array(repeating: "", count: voices)
            } catch {
                NSLog("Bkdict: separador de vozes: \(error.localizedDescription)")
            }
        }
        meeting.status = .summarizing
        save(meeting)
    }

    // MARK: - Voices

    func rename(_ id: String, speaker: Int, to name: String) {
        guard var meeting = meetings.first(where: { $0.id == id }) else { return }
        var names = meeting.speakers ?? []
        while names.count <= speaker { names.append("") }
        names[speaker] = name.trimmingCharacters(in: .whitespaces)
        meeting.speakers = names
        save(meeting)
    }

    /// Gives one segment to a voice; `nil` creates a new voice for it.
    func setSpeaker(_ id: String, segment index: Int, to speaker: Int?) {
        guard var meeting = meetings.first(where: { $0.id == id }), meeting.segments.indices.contains(index) else { return }
        var names = meeting.speakers ?? []
        let voice = speaker ?? names.count
        while names.count <= voice { names.append("") }
        meeting.speakers = names
        meeting.segments[index].speaker = voice
        // A voice left with no lines goes away, and the voices after it move up.
        for empty in (0..<names.count).reversed() where !meeting.segments.contains(where: { $0.speaker == empty }) {
            meeting.segments = meeting.segments.map { segment in
                var copy = segment
                if let voice = segment.speaker, voice > empty { copy.speaker = voice - 1 }
                return copy
            }
            meeting.speakers?.remove(at: empty)
        }
        save(meeting)
    }

    /// Moves a voice's segments to another voice and drops it, renumbering the voices after it.
    func merge(_ id: String, speaker: Int, into target: Int) {
        guard speaker != target, var meeting = meetings.first(where: { $0.id == id }) else { return }
        let destination = target > speaker ? target - 1 : target
        meeting.segments = meeting.segments.map { segment in
            var copy = segment
            if let voice = segment.speaker {
                copy.speaker = voice == speaker ? destination : voice > speaker ? voice - 1 : voice
            }
            return copy
        }
        var names = meeting.speakers ?? []
        if speaker < names.count {
            let dropped = names.remove(at: speaker)
            // Keep the merged voice's name when the destination has none.
            if destination < names.count, names[destination].isEmpty { names[destination] = dropped }
        }
        meeting.speakers = names
        save(meeting)
    }

    private func summarize(_ meeting: inout Meeting) async {
        if meeting.segments.isEmpty {
            meeting.summary = "## Resumo\nNenhuma fala foi captada nesta gravação."
        } else {
            do {
                meeting.summary = try await LLM.summarizeMeeting(meeting.transcript)
            } catch {
                meeting.summary = "## Resumo\nO resumo não foi gerado: \(error.localizedDescription). "
                    + "Configure a IA em Modelos e use \u{201C}Refazer resumo\u{201D}."
            }
        }
        meeting.status = .ready
        save(meeting)
    }

    // MARK: - Formats

    private static let idFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM, HH:mm"
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Finds the stretches with speech in a track, and removes the echo of the others picked up by the microphone.
enum SpeechDetector {
    private static let window = 480 // 30 ms at 16 kHz
    private static let windowSeconds = 0.03

    /// Speech stretches by energy: louder than max(0.008, min(3 × the 10th percentile, the 90th percentile / 2)),
    /// joined across gaps under 0.8 s, at least 0.4 s long, cut at 30 s, with 0.2 s of margin. Percentiles, not the
    /// median: on a track that is mostly speech (the others, in a lively call) the median falls inside the speech
    /// and nothing would be detected.
    static func segments(in url: URL) -> [ClosedRange<TimeInterval>] {
        let levels = WavFileWriter.levels(in: url, window: window)
        guard !levels.isEmpty else { return [] }
        let sorted = levels.sorted()
        let floor = sorted[sorted.count / 10], loud = sorted[sorted.count * 9 / 10]
        let threshold = max(0.008, min(3 * floor, loud / 2))

        var runs: [(start: Int, end: Int)] = []
        var start: Int?
        for (index, level) in levels.enumerated() {
            if level >= threshold {
                if start == nil { start = index }
            } else if let open = start {
                runs.append((open, index))
                start = nil
            }
        }
        if let open = start { runs.append((open, levels.count)) }

        let maxGap = Int(0.8 / windowSeconds)
        var merged: [(start: Int, end: Int)] = []
        for run in runs {
            if let last = merged.last, run.start - last.end < maxGap {
                merged[merged.count - 1].end = run.end
            } else {
                merged.append(run)
            }
        }

        let minLength = Int(0.4 / windowSeconds), maxLength = Int(30 / windowSeconds)
        var pieces: [(start: Int, end: Int)] = []
        for run in merged where run.end - run.start >= minLength {
            var from = run.start
            while run.end - from > maxLength {
                // Cut at the quietest moment of the last 5 s before the limit.
                let searchStart = from + maxLength - Int(5 / windowSeconds)
                let cut = (searchStart..<(from + maxLength)).min { levels[$0] < levels[$1] } ?? from + maxLength
                pieces.append((from, cut))
                from = cut
            }
            pieces.append((from, run.end))
        }

        let duration = Double(levels.count) * windowSeconds
        return pieces.map {
            max(0, Double($0.start) * windowSeconds - 0.2)...min(duration, Double($0.end) * windowSeconds + 0.2)
        }
    }

    static func isSilent(_ url: URL) -> Bool {
        (WavFileWriter.levels(in: url, window: window).max() ?? 0) < 0.0005
    }

    /// Without headphones the microphone also hears the others through the speakers. A "Você" segment that
    /// overlaps an "Eles" one and shares at least 60% of its words with it is that echo.
    static func removingEcho(_ segments: [Meeting.Segment]) -> [Meeting.Segment] {
        let theirs = segments.filter { $0.source == .them }
        return segments.filter { segment in
            guard segment.source == .me else { return true }
            let mine = words(segment.text)
            guard !mine.isEmpty else { return false }
            return !theirs.contains { other in
                other.start < segment.end && segment.start < other.end
                    && Double(mine.filter(Set(words(other.text)).contains).count) / Double(mine.count) >= 0.6
            }
        }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
