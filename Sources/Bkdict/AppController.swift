import AppKit
import SwiftUI
import AVFoundation
import Combine
import Sparkle

/// Menu bar app that wires the global shortcuts to recording, transcription and insertion.
final class AppController: NSObject, NSApplicationDelegate {
    private enum Mode { case dictation, command }

    private struct Session {
        var mode: Mode
        let startedAt = Date()
        var handsFree = false
        var selection: Task<String?, Never>?
    }

    private let model = AppModel()
    private let whisper = WhisperServer()
    private let recorder = AudioRecorder()
    private let overlay = OverlayWindow()
    @MainActor private lazy var meetings = MeetingCenter()
    @MainActor private lazy var detector = MeetingDetector()
    private var offerTimeout: DispatchWorkItem?
    private var mistakeTimeout: DispatchWorkItem?
    private lazy var mainWindow = MainWindowController(model: model, meetings: MainActor.assumeIsolated { meetings })
    private let meetingItem = NSMenuItem(title: "Gravar reunião", action: nil, keyEquivalent: "")
    private let hotkey = HotkeyMonitor()
    /// Checks the release appcast on its own schedule (SUEnableAutomaticChecks) and installs updates on request.
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Iniciando…", action: nil, keyEquivalent: "")
    private var session: Session?
    private var permissionTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    private static let minimumDuration: TimeInterval = 0.35

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.apply(Settings.appearance)
        NSApp.mainMenu = MainMenu.make()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The mark as a template image, so macOS tints it for the menu bar's appearance.
        let icon = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "BKDict")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "BKDict"
        statusItem.button?.image = icon
        buildMenu()
        mainWindow.show()

        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.overlay.state.level = level }
        }
        hotkey.onAction = { [weak self] action in self?.handle(action) }
        hotkey.isRecording = { [weak self] in self?.session != nil }
        hotkey.isPaused = { [weak self] in self?.model.isRecordingShortcut == true }
        hotkey.transformIndex = { [weak self] code, flags, baseDown in
            guard let model = self?.model, model.transformsEnabled else { return nil }
            return model.transforms.indices.first { index in
                // Positional defaults only apply while the base key is held.
                guard model.transforms[index].shortcut != nil || baseDown,
                      let combo = model.shortcut(for: index) else { return false }
                return combo.matches(keyCode: code, flags: flags)
            }
        }
        hotkey.isHandsFree = { [weak self] in self?.session?.handsFree == true }
        hotkey.shortcuts = model.shortcuts
        model.onShortcutsChange = { [weak self] shortcuts in
            self?.hotkey.shortcuts = shortcuts
            self?.overlay.state.dictateKeys = self?.model.keys(for: .dictate) ?? []
            if self?.model.isReady == true { self?.setReady() }
        }
        setUpDictationBar()
        setUpMeetings()
        model.onEngineChange = { [weak self] in
            Task { @MainActor in await self?.prepareEngine() }
        }

        model.requestMicrophone()
        startHotkeyWhenTrusted()
        Task { @MainActor in await prepareEngine() }
        Task { @MainActor in await installOllama() }
    }

    /// Installs Ollama on first launch so local AI only needs a model, and starts it when it is the chosen AI.
    @MainActor
    private func installOllama() async {
        await Dependency.ollama.install()
        if Settings.llmProvider == .ollama { await model.ollama.start() }
    }

    /// Starts or stops the local server to match the selected transcription engine.
    @MainActor
    private func prepareEngine() async {
        model.isReady = false
        switch Settings.transcriptionEngine {
        case .cloud:
            whisper.stop()
            let provider = Settings.transcriptionProvider
            guard Keychain.key(for: provider) != nil else {
                setStatus(CloudTranscriber.Failure.missingKey(provider).localizedDescription)
                return
            }
        case .local:
            if Dependency.whisper.binaryPath == nil {
                let progress = Dependency.whisper.$state.sink { [weak self] state in
                    if case .installing(let fraction) = state {
                        self?.setStatus("Instalando o whisper… \(Int(fraction * 100))%")
                    }
                }
                await Dependency.whisper.install()
                progress.cancel()
                if case .failed(let message) = Dependency.whisper.state {
                    setStatus(message)
                    return
                }
            }
            setStatus("Carregando modelo…")
            do {
                try await whisper.restart()
            } catch {
                setStatus(error.localizedDescription)
                return
            }
        }
        if AXIsProcessTrusted() { setReady() } else { setStatus("Permita o BKDict em Acessibilidade") }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { meetings.stopForQuit() }
        whisper.stop()
        model.ollama.stop()
    }

    // MARK: - Permissions

    private func startHotkeyWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), hotkey.start() { return }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.hotkey.start() else { return }
            timer.invalidate()
            self.model.refreshPermissions()
            if self.statusLine.title.hasPrefix("Permita") { Task { @MainActor in await self.prepareEngine() } }
        }
    }

    // MARK: - Shortcuts

    private func handle(_ action: HotkeyMonitor.Action) {
        switch action {
        case .holdStart(.command):
            begin(.command)
        case .holdStart:
            begin(.dictation)
        case .switchToCommand:
            switchToCommand()
        case .holdEnd:
            if session?.handsFree == false { finish() }
        case .handsFree:
            toggleHandsFree()
        case .stop:
            finish()
        case .cancel:
            cancel()
        case .discard:
            discardRecording()
        case .pasteLast:
            if let last = model.history.first { TextInserter.insert(last.text) }
        case .copyLast:
            copyLast()
        case .transform(let index):
            if session?.handsFree == false { discardRecording() }
            runTransform(index)
        }
    }

    /// Starts a hands-free dictation, locks the one being held, or stops a hands-free one.
    private func toggleHandsFree() {
        guard let current = session else {
            begin(.dictation)
            guard session != nil else { return }
            session?.handsFree = true
            overlay.show(.handsFree)
            return
        }
        if current.handsFree {
            finish()
            return
        }
        session?.handsFree = true
        overlay.show(current.mode == .command ? .command : .handsFree)
        play("Tink")
    }

    // MARK: - Dictation

    private func begin(_ mode: Mode) {
        guard session == nil else { return }
        do {
            try recorder.start()
        } catch {
            flashError("Microfone indisponível")
            return
        }
        session = Session(mode: mode)
        if mode == .command { captureSelection() }
        overlay.show(mode == .command ? .command : .listening)
        play("Pop")
    }

    private func switchToCommand() {
        guard session != nil else { return }
        session?.mode = .command
        captureSelection()
        overlay.show(.command)
    }

    private func captureSelection() {
        session?.selection = Task { @MainActor in await TextInserter.selectedText() }
    }

    /// Meetings share the dictation's transcription and corrections, and show in the bar and the menu.
    @MainActor
    private func setUpMeetings() {
        meetings.transcribe = { [weak self] wav in
            guard let self else { return "" }
            return try await self.transcribe(wav)
        }
        meetings.correct = { [weak self] text in
            TextProcessor.apply(text, replacements: self?.model.replacements ?? [], snippets: [])
        }
        overlay.state.onToggleMeeting = { [weak self] in self?.toggleMeeting() }
        overlay.state.onStartMeeting = { [weak self] in
            guard let self, self.meetings.recordingSince == nil else { return }
            self.meetings.start()
        }
        overlay.state.onToggleLive = { [weak self] in
            guard let self else { return }
            self.overlay.state.liveVisible.toggle()
        }
        overlay.state.onResolveMistake = { [weak self] keep in
            self?.mistakeTimeout?.cancel()
            self?.meetings.resolveMistake(keep: keep)
        }
        overlay.state.onAcceptOffer = { [weak self] offer in
            guard let self else { return }
            self.clearOffer()
            switch offer {
            case .record(let app): self.meetings.start(app: app)
            case .stop: self.meetings.stop()
            }
        }
        // The detector reports each call once, so a dismissed offer does not come back for the same call.
        overlay.state.onDismissOffer = { [weak self] in self?.clearOffer() }
        detector.isEnabled = { [weak self] in self?.model.detectMeetings ?? false }
        detector.onCallStarted = { [weak self] app in
            guard let self, self.meetings.recordingSince == nil else { return }
            if self.model.autoRecordMeetings {
                self.meetings.start(app: app)
            } else {
                self.showOffer(.record(app: app), for: 20)
            }
        }
        detector.onCallEnded = { [weak self] app in
            guard let self else { return }
            if self.meetings.recordingSince != nil {
                if self.model.autoRecordMeetings { self.meetings.stop() } else { self.showOffer(.stop(app: app), for: 30) }
            } else if case .record = self.overlay.state.offer {
                self.clearOffer()
            }
        }
        detector.start()
        meetings.$recordingSince.sink { [weak self] since in
            self?.overlay.state.meetingSince = since
            // Recording started some other way: the offer to record is moot.
            if since != nil, case .record = self?.overlay.state.offer { self?.clearOffer() }
            self?.meetingItem.title = since == nil ? "Gravar reunião" : "Parar gravação da reunião"
            // The live transcript belongs to the recording: it closes with it.
            if since == nil { self?.overlay.state.liveVisible = false }
            self?.overlay.layout()
        }
        .store(in: &subscriptions)
        meetings.$live.sink { [weak self] live in
            withAnimation(.easeOut(duration: 0.25)) { self?.overlay.state.live = live }
        }
        .store(in: &subscriptions)
        // "Começou sem querer?" stays 15 s; with no answer the meeting is kept.
        meetings.$suspectedMistake.sink { [weak self] id in
            guard let self else { return }
            self.mistakeTimeout?.cancel()
            self.overlay.state.mistake = id != nil
            self.overlay.layout()
            guard id != nil else { return }
            let timeout = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.meetings.resolveMistake(keep: true) }
            }
            self.mistakeTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        }
        .store(in: &subscriptions)
    }

    @MainActor
    private func showOffer(_ offer: MeetingOffer, for seconds: TimeInterval) {
        offerTimeout?.cancel()
        overlay.state.offer = offer
        overlay.layout()
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.clearOffer() }
        }
        offerTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    @MainActor
    private func clearOffer() {
        offerTimeout?.cancel()
        overlay.state.offer = nil
        overlay.layout()
    }

    @MainActor @objc private func toggleMeeting() {
        if meetings.recordingSince == nil { meetings.start() } else { meetings.stop() }
    }

    /// The bar's buttons and menu, and the settings it follows.
    private func setUpDictationBar() {
        let bar = overlay.state
        bar.dictateKeys = model.keys(for: .dictate)
        bar.onDictate = { [weak self] in self?.toggleHandsFree() }
        bar.onStop = { [weak self] in
            if self?.session != nil { self?.finish() }
        }
        bar.onCancel = { [weak self] in self?.cancel() }
        bar.onPasteLast = { [weak self] in
            if let last = self?.model.history.first { TextInserter.insert(last.text) }
        }
        // Copying is the person's choice here, so it replaces the clipboard on purpose.
        bar.onCopyUnplaced = { [weak self] in
            guard case .unplaced(let text) = self?.overlay.state.phase else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.overlay.state.phase == .unplaced(text) { self?.overlay.show(.hidden) }
            }
        }
        bar.onDismissUnplaced = { [weak self] in self?.overlay.show(.hidden) }
        bar.onOpenApp = { [weak self] in self?.mainWindow.show() }
        bar.onSelectMicrophone = { [weak self] in self?.model.microphone = $0 }
        model.$microphone.sink { [weak self] in self?.overlay.state.microphone = $0 }.store(in: &subscriptions)
        model.$showsDictationBar.sink { [weak self] in self?.overlay.showsIdleBar = $0 }.store(in: &subscriptions)
        // Follow the Dock, resolution and monitor changes.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.overlay.layout() }
            .store(in: &subscriptions)
        overlay.layout()
    }

    private func cancel() {
        guard session != nil else { return }
        discardRecording()
        play("Bottle")
    }

    private func discardRecording() {
        guard session != nil else { return }
        session = nil
        _ = recorder.stop()
        overlay.show(.hidden)
    }

    /// Applies a saved transform to the focused app's selected text.
    private func runTransform(_ index: Int) {
        guard model.transforms.indices.contains(index) else {
            flashError("Nenhum transform no \(index + 1)")
            return
        }
        let transform = model.transforms[index]
        Task { @MainActor in
            guard let text = await TextInserter.selectedText() else {
                flashError("Selecione um texto primeiro")
                return
            }
            overlay.show(.transforming(transform.name))
            do {
                let result = try await LLM.transform(text, with: transform.prompt)
                overlay.show(.hidden)
                TextInserter.insert(result)
            } catch {
                flashError(Self.message(for: error))
            }
        }
    }

    private func finish() {
        guard let session else { return }
        self.session = nil
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(session.startedAt)

        guard duration >= Self.minimumDuration, !samples.isEmpty else {
            overlay.show(.hidden)
            return
        }
        play("Morse")
        overlay.show(.transcribing)

        Task { @MainActor in
            do {
                let spoken = try await transcribe(AudioRecorder.wavData(from: samples))
                guard !spoken.isEmpty else {
                    overlay.show(.hidden)
                    return
                }

                let text: String
                switch session.mode {
                case .dictation:
                    text = try await processDictation(spoken)
                case .command:
                    overlay.show(.thinking)
                    text = try await LLM.command(spoken, selection: await session.selection?.value)
                }

                model.add(Dictation(date: Date(), text: text, duration: duration))
                // Like a person would, paste only into a text box; otherwise keep it for the paste shortcut.
                if TextInserter.focusedTarget() == .notEditable {
                    showUnplaced(text)
                } else {
                    overlay.show(.hidden)
                    TextInserter.insert(text)
                }
            } catch {
                flashError(Self.message(for: error))
                NSLog("BKDict: \(error.localizedDescription)")
            }
        }
    }

    private func transcribe(_ wav: Data) async throws -> String {
        let prompt = TextProcessor.whisperPrompt(for: model.dictionary)
        switch Settings.transcriptionEngine {
        case .local:
            return try await whisper.transcribe(wav: wav, language: Settings.language, prompt: prompt)
        case .cloud:
            return try await CloudTranscriber.transcribe(wav: wav, language: Settings.language, prompt: prompt)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let error as LLM.Failure: return error.localizedDescription
        case let error as CloudTranscriber.Failure: return error.localizedDescription
        case let error as WhisperServer.Failure: return error.localizedDescription
        default: return "Falha na transcrição"
        }
    }

    @MainActor
    private func processDictation(_ spoken: String) async throws -> String {
        var text = spoken
        if Settings.polishEnabled {
            overlay.show(.polishing)
            text = (try? await LLM.polish(text)) ?? text
        }
        if let transform = model.autoTransform {
            overlay.show(.transforming(transform.name))
            text = (try? await LLM.transform(text, with: transform.prompt)) ?? text
        }
        return TextProcessor.apply(text, replacements: model.replacements, snippets: model.snippets)
    }

    /// The card stays 12 s, longer while the mouse is on it, so the text can be read and copied.
    private func showUnplaced(_ text: String) {
        overlay.state.pasteKeys = model.keys(for: .pasteLast)
        overlay.show(.unplaced(text))
        scheduleUnplacedDismiss(after: 12, text: text)
    }

    private func scheduleUnplacedDismiss(after seconds: TimeInterval, text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.overlay.state.phase == .unplaced(text) else { return }
            if self.overlay.state.hovering { return self.scheduleUnplacedDismiss(after: 3, text: text) }
            self.overlay.show(.hidden)
        }
    }

    private func flashError(_ message: String) {
        overlay.show(.error(message))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if case .error = self?.overlay.state.phase { self?.overlay.show(.hidden) }
        }
    }

    private func play(_ sound: String) {
        guard Settings.soundsEnabled else { return }
        NSSound(named: sound)?.play()
    }

    // MARK: - Status & menu

    private func setReady() {
        model.isReady = true
        setStatus("Pronto — segure \(model.dictateLabel) para ditar")
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        model.status = text
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Abrir BKDict", action: #selector(openMainWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let copyLast = NSMenuItem(title: "Copiar última transcrição", action: #selector(copyLast), keyEquivalent: "c")
        copyLast.target = self
        menu.addItem(copyLast)

        meetingItem.action = #selector(toggleMeeting)
        meetingItem.target = self
        menu.addItem(meetingItem)

        let update = NSMenuItem(title: "Procurar atualizações…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do BKDict", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        mainWindow.show()
    }

    @objc private func copyLast() {
        guard let last = model.history.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
    }
}
