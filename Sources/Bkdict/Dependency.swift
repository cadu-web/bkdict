import Foundation

/// A command-line tool the app installs by itself on first launch, into Application Support, so nobody needs
/// Homebrew or the Terminal. The models stay the person's choice; only the programs that run them come preinstalled.
/// `state` changes only on the main actor, inside `install()`; the rest is immutable, hence the unchecked Sendable.
final class Dependency: ObservableObject, @unchecked Sendable {
    enum State: Equatable {
        case missing
        case installing(Double)
        case installed
        case failed(String)
    }

    /// whisper.cpp's server, built by us (scripts/build-whisper.sh) because upstream ships no macOS binary.
    static let whisper = Dependency(
        title: "whisper",
        folder: "whisper",
        executable: "whisper-server",
        archive: URL(string: "https://github.com/cadu-web/bkdict/releases/download/whisper-v1.9.5/whisper-server-macos.tgz")!,
        fallbacks: ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
    )

    /// Ollama's official macOS command-line build.
    static let ollama = Dependency(
        title: "Ollama",
        folder: "ollama",
        executable: "ollama",
        archive: URL(string: "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz")!,
        fallbacks: ["/Applications/Ollama.app/Contents/Resources/ollama", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
    )

    let title: String
    private let folder: String
    private let executable: String
    private let archive: URL
    private let fallbacks: [String]

    @Published private(set) var state: State

    private init(title: String, folder: String, executable: String, archive: URL, fallbacks: [String]) {
        self.title = title
        self.folder = folder
        self.executable = executable
        self.archive = archive
        self.fallbacks = fallbacks
        let present = Self.locate(folder: folder, executable: executable, fallbacks: fallbacks) != nil
        _state = Published(initialValue: present ? .installed : .missing)
    }

    private var directory: URL {
        Settings.supportDirectory.appendingPathComponent(folder, isDirectory: true)
    }

    /// The installed copy, or one the person already had (Homebrew, Ollama.app).
    var binaryPath: String? {
        Self.locate(folder: folder, executable: executable, fallbacks: fallbacks)
    }

    private static func locate(folder: String, executable: String, fallbacks: [String]) -> String? {
        let installed = Settings.supportDirectory.appendingPathComponent(folder).appendingPathComponent(executable).path
        return ([installed] + fallbacks).first(where: FileManager.default.isExecutableFile)
    }

    /// Downloads and unpacks the tool. Safe to call repeatedly: it returns at once if the tool is there or on its way.
    @MainActor
    func install() async {
        if binaryPath != nil {
            state = .installed
            return
        }
        if case .installing = state { return }
        state = .installing(0)

        let fileManager = FileManager.default
        let staging = Settings.supportDirectory.appendingPathComponent(".\(folder)-install", isDirectory: true)
        do {
            let progress = DownloadProgress { [weak self] fraction in
                Task { @MainActor in
                    if case .installing = self?.state { self?.state = .installing(fraction) }
                }
            }
            let (file, response) = try await URLSession.shared.download(from: archive, delegate: progress)
            defer { try? fileManager.removeItem(at: file) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw InstallError("o download respondeu \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }

            // Unpack next to the final folder and swap it in only when complete, so a failed install leaves nothing half-done.
            try? fileManager.removeItem(at: staging)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try await Self.untar(file, into: staging)
            guard fileManager.isExecutableFile(atPath: staging.appendingPathComponent(executable).path) else {
                throw InstallError("o pacote não tem o \(executable)")
            }
            try? fileManager.removeItem(at: directory)
            try fileManager.moveItem(at: staging, to: directory)
            state = .installed
        } catch {
            try? fileManager.removeItem(at: staging)
            state = .failed("Não foi possível instalar o \(title): \(error.localizedDescription)")
        }
    }

    private static func untar(_ archive: URL, into directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InstallError("não foi possível descompactar o pacote"))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

private struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Reports a download's progress by watching the task the async download call creates.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}
