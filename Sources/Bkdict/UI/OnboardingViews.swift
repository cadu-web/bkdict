import AppKit
import AVFoundation
import Combine
import SwiftUI

/// First-launch setup: permissions, microphone and a transcription model, on one screen.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let onFinish: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    /// Needed until it's finished once. Someone who already set BKDict up before it existed skips it.
    /// `open BKDict.app --args --onboarding` shows it again on a Mac that is set up, and `--onboarding-demo`
    /// shows it as a new Mac sees it (nothing granted, the model downloading).
    static var isNeeded: Bool {
        if CommandLine.arguments.contains("--onboarding") || OnboardingView.demo { return true }
        guard !Settings.onboardingDone else { return false }
        if AXIsProcessTrusted() && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            Settings.onboardingDone = true
            return false
        }
        return true
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Bem-vindo ao BKDict"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(model: model, manager: model.models) { [weak self] in
                self?.finish()
            })
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        Settings.onboardingDone = true
        window?.delegate = nil
        window?.close()
        window = nil
        onFinish()
    }

    /// Closing it early still opens the app; it comes back on the next launch until it's finished.
    func windowWillClose(_ notification: Notification) {
        window = nil
        onFinish()
    }
}

/// One screen, one checklist: each item shows what's left to do and turns green when it's done.
private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var manager: ModelManager
    @ObservedObject private var whisper = Dependency.whisper
    let finish: () -> Void

    static let demo = CommandLine.arguments.contains("--onboarding-demo")
    @State private var demoProgress = 0.0
    @State private var choosing = false
    @StateObject private var meter = MicrophoneMeter()

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var item: WhisperModel { ModelManager.recommended }
    private var microphoneGranted: Bool { !Self.demo && model.microphoneGranted }
    private var accessibilityGranted: Bool { !Self.demo && model.accessibilityGranted }

    /// The whisper server and the chosen model are on the Mac, or the chosen provider has a key.
    private var modelReady: Bool {
        if Self.demo { return demoProgress >= 1 }
        guard model.transcriptionEngine == .local else { return model.savedKeys.contains(model.transcriptionProvider) }
        return whisper.state == .installed && manager.installed.contains(model.localModel)
    }

    /// What is downloading for transcription and how far along: the whisper server first, then the model.
    private var download: (label: String, progress: Double)? {
        if Self.demo { return modelReady ? nil : ("o \(item.name)", demoProgress) }
        guard model.transcriptionEngine == .local, !modelReady else { return nil }
        if case .installing(let fraction) = whisper.state { return ("o whisper", fraction) }
        for id in [model.localModel, item.id] {
            if let progress = manager.progress[id], let downloading = ModelManager.catalog.first(where: { $0.id == id }) {
                return ("o \(downloading.name)", progress)
            }
        }
        return nil
    }

    private var allDone: Bool { microphoneGranted && accessibilityGranted && modelReady }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    Text("Bem-vindo ao BKDict")
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.text)
                    Text("Segure \(model.dictateLabel), fale e solte: o texto aparece onde o cursor estiver. Falta só isto:")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    microphone
                    accessibility
                    transcription
                }
                .card(padding: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 36)

            HStack {
                Text(allDone ? "Tudo pronto." : "Dá para terminar depois em Ajustes e Modelos.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if allDone {
                    Button("Começar a usar", action: done)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Fazer depois", action: done)
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Divider().overlay(Theme.border) }
        }
        .frame(width: 720, height: 620)
        .background(Theme.background)
        .tint(Theme.accent)
        .onReceive(permissionTimer) { _ in
            model.refreshPermissions()
            if Self.demo { demoProgress = min(demoProgress + 0.04, 1) }
        }
        .onAppear {
            prepareModel()
            updateMeter()
        }
        .onDisappear { meter.stop() }
        .onChange(of: manager.installed) { prepareModel() }
        .onChange(of: microphoneGranted) { updateMeter() }
        .onChange(of: model.microphone) { if meter.isRunning { meter.start() } }
    }

    private func done() {
        meter.stop()
        finish()
    }

    // MARK: Items

    private var microphone: some View {
        ChecklistItem(done: microphoneGranted, title: "Liberar o microfone",
                      detail: microphoneGranted ? "Fale para testar" : "Só ouve enquanto você segura o atalho") {
            if microphoneGranted {
                MicrophoneLevel(levels: meter.levels)
                MicrophonePicker(selection: $model.microphone, width: 170)
            } else if !Self.demo && AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                Button("Abrir Ajustes", action: model.openMicrophoneSettings).buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Permitir", action: model.requestMicrophone).buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var accessibility: some View {
        ChecklistItem(done: accessibilityGranted, title: "Liberar a Acessibilidade",
                      detail: accessibilityGranted ? "Para perceber o atalho e colar o texto"
                                                   : "Clique em Abrir Ajustes e ative o BKDict na lista") {
            if !accessibilityGranted {
                Button("Abrir Ajustes", action: model.requestAccessibility).buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var transcription: some View {
        ChecklistItem(done: modelReady, title: "Preparar a transcrição", detail: transcriptionDetail, divider: false) {
            if let download {
                ProgressView(value: download.progress).frame(width: 110)
            }
            Button(modelReady ? "Trocar" : "Escolher") { choosing = true }
                .buttonStyle(SecondaryButtonStyle())
        }
        .sheet(isPresented: $choosing) {
            ModelChooser(model: model, manager: manager) { choosing = false }
        }
    }

    private var transcriptionDetail: String {
        if let download {
            let percent = download.progress.formatted(.percent.precision(.fractionLength(0)))
            return "Baixando \(download.label)… \(percent)"
        }
        if model.transcriptionEngine == .cloud {
            let provider = model.transcriptionProvider
            return modelReady ? "\(provider.title) · \(model.transcriptionModel), com a sua chave"
                              : "Falta a chave da \(provider.title): clique em Escolher"
        }
        if case .failed(let message) = whisper.state { return message }
        if modelReady, let selected = ModelManager.catalog.first(where: { $0.id == model.localModel }) {
            return "Whisper \(selected.name) · no seu Mac, grátis e offline"
        }
        return manager.lastError ?? "Preparando…"
    }

    /// Without a usable model, downloads the recommended one by itself and uses it when it's ready. Someone who
    /// picked another model, or an API key, keeps their choice. The whisper server installs on launch.
    private func prepareModel() {
        guard !Self.demo, model.transcriptionEngine == .local, !manager.installed.contains(model.localModel) else { return }
        if manager.installed.contains(item.id) {
            model.localModel = item.id
        } else if manager.progress[item.id] == nil {
            manager.download(item)
        }
    }

    /// Listens only while the microphone is allowed; the levels stay on this screen and no audio is kept.
    private func updateMeter() {
        if microphoneGranted { meter.start() } else { meter.stop() }
    }
}

/// The same transcription choices as Modelos, in a sheet: a model to download, or an API key.
private struct ModelChooser: View {
    @ObservedObject var model: AppModel
    @ObservedObject var manager: ModelManager
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modelo de transcrição")
                            .font(Theme.display(26))
                            .foregroundStyle(Theme.text)
                        Text("Baixe um modelo para usar neste Mac ou conecte sua chave de API. Dá para trocar depois em Modelos.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.secondary)
                    }
                    SectionCard {
                        SettingRow(title: "Idioma em que você vai falar", divider: false) {
                            Picker("", selection: $model.language) {
                                Text("Português").tag("pt")
                                Text("English").tag("en")
                                Text("Español").tag("es")
                                Text("Detectar automaticamente").tag("auto")
                            }
                            .labelsHidden()
                            .frame(width: 200)
                        }
                    }
                    TranscriptionCard(model: model, manager: manager)
                }
                .padding(28)
            }
            HStack {
                Text("Baixar um modelo não troca o que está em uso: clique em Usar quando terminar.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Pronto", action: done)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Divider().overlay(Theme.border) }
        }
        .frame(width: 720, height: 580)
        .background(Theme.background)
        .onAppear { manager.refresh() }
    }
}

/// A row with a check that turns green when done, and the action (if any) on the right.
private struct ChecklistItem<Trailing: View>: View {
    let done: Bool
    let title: String
    let detail: String
    var divider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(done ? Theme.ready : Theme.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .animation(.easeOut(duration: 0.2), value: done)
            if divider { Divider().overlay(Theme.border).padding(.leading, 48) }
        }
    }
}

/// Bars for the microphone's last levels, newest on the right, so speaking makes them move.
private struct MicrophoneLevel: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent)
                    .frame(width: 3, height: 3 + 15 * Self.loudness(levels[index]))
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    /// Decibels rather than raw RMS: a normal voice sits around -30 dBFS, which barely moves a linear bar.
    private static func loudness(_ rms: Float) -> CGFloat {
        let decibels = 20 * log10(max(rms, 1e-6))
        return CGFloat(min(max((decibels + 55) / 40, 0), 1))
    }
}

/// Listens to the chosen microphone for the level bars. Keeps no audio.
private final class MicrophoneMeter: ObservableObject {
    @Published private(set) var levels = [Float](repeating: 0, count: 14)
    private(set) var isRunning = false
    private let recorder = AudioRecorder()

    init() {
        recorder.keepsSamples = false
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.levels.removeFirst()
                self.levels.append(level)
            }
        }
    }

    /// Starts, or restarts on the microphone now in `Settings.microphone`.
    func start() {
        stop()
        isRunning = (try? recorder.start()) != nil
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        _ = recorder.stop()
        levels = levels.map { _ in 0 }
    }
}
