import AppKit
import Combine
import SwiftUI

/// Where the bar sits: like a dock, it snaps to one of three places on the screen with the mouse.
enum DockEdge: String, CaseIterable, Identifiable {
    case bottom, left, right

    var id: Self { self }
    var title: String {
        switch self {
        case .bottom: "Embaixo"
        case .left: "Esquerda"
        case .right: "Direita"
        }
    }
}

final class OverlayState: ObservableObject {
    enum Phase: Equatable {
        case hidden, listening, handsFree, command, transcribing, polishing, thinking
        case transforming(String)
        case error(String)
        /// Guidance rather than a failure, e.g. where a dictation went when it could not be pasted.
        case tip(String)
    }

    @Published var phase: Phase = .hidden
    @Published var level: Float = 0
    @Published var hovering = false
    /// The dictation shortcut, shown when the idle bar is hovered.
    @Published var dictateKeys: [String] = []
    /// The microphone setting, for the bar's menu (a device UID or Microphones.automatic).
    @Published var microphone = Settings.microphone
    @Published var edge = Settings.dictationBarEdge
    @Published var dragging = false

    var isRecording: Bool { [.listening, .handsFree, .command].contains(phase) }

    // Wired by AppController.
    var onDictate: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    var onPasteLast: () -> Void = {}
    var onOpenApp: () -> Void = {}
    var onHideForAnHour: () -> Void = {}
    var onSelectMicrophone: (String) -> Void = { _ in }
    // Wired by OverlayWindow, which owns the panel.
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onSelectEdge: (DockEdge) -> Void = { _ in }
}

/// The dictation bar, docked at the bottom or on a side of the screen. Idle, it is a small handle that grows on hover into a
/// "Ditar" button; while dictating it shows the waveform with cancel and finish buttons; then the progress.
/// It is a non-activating panel, so clicking it never takes focus from the app the text goes to.
final class OverlayWindow {
    let state = OverlayState()
    private let panel: NSPanel
    private let guide = DockGuideWindow()
    private var hiddenUntil: Date?
    /// Where the mouse grabbed the bar, while it is being dragged.
    private var dragOffset: NSPoint?
    /// Off in Settings, the bar only appears while dictating, as the indicator.
    var showsIdleBar = Settings.showsDictationBar {
        didSet { layout() }
    }

    private enum Size {
        static let idle = NSSize(width: 44, height: 8)
        static let idleSide = NSSize(width: 8, height: 44)
        static let hovered = NSSize(width: 168, height: 36)
        static let recording = NSSize(width: 300, height: 40)
        static let busy = NSSize(width: 260, height: 40)
        static let tip = NSSize(width: 380, height: 40)
        // On a side the whole bar stands up.
        static let hoveredSide = NSSize(width: 52, height: 112)
        static let recordingSide = NSSize(width: 40, height: 104)
        static let busySide = NSSize(width: 40, height: 40)
    }

    init() {
        panel = BarPanel(
            contentRect: NSRect(origin: .zero, size: Size.idle),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = FirstClickHostingView(rootView: BarView(state: state))
        state.onHideForAnHour = { [weak self] in self?.hide(for: 3600) }
        state.onDragChanged = { [weak self] in self?.dragChanged() }
        state.onDragEnded = { [weak self] in self?.dragEnded() }
        state.onSelectEdge = { [weak self] in self?.dock(at: $0) }
        // Hover changes the size; layout is deferred so SwiftUI finishes the current update first.
        hoverObservation = state.$hovering.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }
        // With several monitors the bar sits on the one with the mouse, and moves when the mouse does.
        screenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.state.phase == .hidden, self.dragOffset == nil, Self.mouseScreen != self.currentScreen else { return }
            self.layout()
        }
    }

    private static var mouseScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private var hoverObservation: Any?
    private var screenTimer: Timer?
    private var currentScreen: NSScreen?

    func show(_ phase: OverlayState.Phase) {
        state.phase = phase
        if phase != .hidden { state.hovering = false }
        layout()
    }

    /// Re-anchors the bar, e.g. after the screens change.
    func layout(animated: Bool = false) {
        guard dragOffset == nil else { return }
        guard let size = currentSize else {
            panel.orderOut(nil)
            return
        }
        guard let screen = Self.mouseScreen else { return }
        currentScreen = screen
        let origin = Self.slot(state.edge, size: size, in: screen.visibleFrame)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
        panel.orderFrontRegardless()
    }

    /// The bar's size for its state, or nil when it should not be on screen.
    private var currentSize: NSSize? {
        let side = state.edge != .bottom
        switch state.phase {
        case .hidden:
            let snoozed = hiddenUntil.map { $0 > Date() } ?? false
            guard showsIdleBar, !snoozed else { return nil }
            if state.hovering { return side ? Size.hoveredSide : Size.hovered }
            return side ? Size.idleSide : Size.idle
        case .listening, .handsFree, .command:
            return side ? Size.recordingSide : Size.recording
        case .tip:
            return side ? Size.busySide : Size.tip
        default:
            return side ? Size.busySide : Size.busy
        }
    }

    /// Bottom center, or the middle of a side, 12 pt from the edge.
    static func slot(_ edge: DockEdge, size: NSSize, in frame: NSRect) -> NSPoint {
        switch edge {
        case .bottom: NSPoint(x: (frame.midX - size.width / 2).rounded(), y: frame.minY + 12)
        case .left: NSPoint(x: frame.minX + 12, y: (frame.midY - size.height / 2).rounded())
        case .right: NSPoint(x: frame.maxX - size.width - 12, y: (frame.midY - size.height / 2).rounded())
        }
    }

    // MARK: - Dragging

    private func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragOffset == nil {
            dragOffset = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            state.dragging = true
        }
        guard let offset = dragOffset, let screen = Self.mouseScreen else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
        guide.show(on: screen, nearest: nearestEdge(to: mouse, on: screen))
        panel.orderFrontRegardless()
    }

    private func dragEnded() {
        guard dragOffset != nil else { return }
        let mouse = NSEvent.mouseLocation
        let edge = Self.mouseScreen.map { nearestEdge(to: mouse, on: $0) } ?? state.edge
        dragOffset = nil
        state.dragging = false
        guide.hide()
        dock(at: edge)
    }

    /// The dock place whose slot is closest to the mouse.
    private func nearestEdge(to point: NSPoint, on screen: NSScreen) -> DockEdge {
        return DockEdge.allCases.min { a, b in distance(a) < distance(b) } ?? .bottom

        func distance(_ edge: DockEdge) -> CGFloat {
            let size = edge == .bottom ? Size.idle : Size.idleSide
            let origin = Self.slot(edge, size: size, in: screen.visibleFrame)
            let dx = origin.x + size.width / 2 - point.x, dy = origin.y + size.height / 2 - point.y
            return dx * dx + dy * dy
        }
    }

    private func dock(at edge: DockEdge) {
        state.edge = edge
        Settings.dictationBarEdge = edge
        layout(animated: true)
    }

    private func hide(for seconds: TimeInterval) {
        hiddenUntil = Date().addingTimeInterval(seconds)
        state.hovering = false
        layout()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.hiddenUntil = nil
            self?.layout()
        }
    }
}

/// Never becomes key, so the focused app keeps the keyboard and receives the paste.
private final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the bar act right away, although its window is never key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct BarView: View {
    @ObservedObject var state: OverlayState

    private static let tinta = Color(hex: 0x0A0A0A)
    static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 10 pt continuous corners, by request: the one deliberate exception to the brand's 4 pt limit.
            .background(Self.shape.fill(Self.tinta.opacity(isIdleHandle ? 0.55 : 0.94)))
            .overlay(Self.shape.strokeBorder(Theme.onAccent.opacity(isIdleHandle ? 0.25 : 0.14)))
            .clipShape(Self.shape)
            .contentShape(Rectangle())
            .onHover { hovering in
                if state.phase == .hidden, !state.dragging { state.hovering = hovering }
            }
            // Positions come from the mouse in screen coordinates: the window moves under the gesture.
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in state.onDragChanged() }
                    .onEnded { _ in state.onDragEnded() }
            )
            .contextMenu {
                Button("Colar a última transcrição", action: state.onPasteLast)
                Menu("Microfone") { MicrophoneMenu(state: state) }
                Menu("Posição") {
                    ForEach(DockEdge.allCases) { edge in
                        Button { state.onSelectEdge(edge) } label: {
                            if state.edge == edge { Label(edge.title, systemImage: "checkmark") } else { Text(edge.title) }
                        }
                    }
                }
                Divider()
                Button("Esconder por 1 hora", action: state.onHideForAnHour)
                Button("Abrir o Bkdict", action: state.onOpenApp)
            }
    }

    private var isIdleHandle: Bool { state.phase == .hidden && !state.hovering }

    @ViewBuilder private var content: some View {
        let side = state.edge != .bottom
        switch state.phase {
        case .hidden:
            if state.hovering { side ? AnyView(idleSide) : AnyView(idle) } else { Color.clear }
        case .listening, .handsFree, .command:
            side ? AnyView(recordingSide) : AnyView(recording)
        default:
            side ? AnyView(busySide) : AnyView(busy)
        }
    }

    // On a side: the same controls, stacked, without the long labels (they show on hover instead).

    private var idleSide: some View {
        VStack(spacing: 6) {
            Text("Ditar")
                .font(Theme.body(11, .medium))
                .foregroundStyle(Theme.onAccent)
            if !state.dictateKeys.isEmpty { KeyCaps(keys: state.dictateKeys, onAccent: true) }
            BarButton(systemImage: "mic.fill", fill: Theme.accentOnTinta, help: "Ditar sem segurar a tecla", action: state.onDictate)
        }
        .padding(.vertical, 8)
    }

    private var recordingSide: some View {
        VStack(spacing: 8) {
            BarButton(systemImage: "xmark", fill: Theme.onAccent.opacity(0.12), help: "Cancelar", action: state.onCancel)
            waveform.help(label)
            BarButton(systemImage: "stop.fill", fill: Theme.accentOnTinta, help: "Finalizar e colar", action: state.onStop)
        }
        .padding(.vertical, 7)
    }

    private var busySide: some View {
        statusIcon.help(label)
    }

    /// Hovered idle bar: what dictates, and a button that starts hands-free.
    private var idle: some View {
        HStack(spacing: 8) {
            Text("Ditar")
                .font(Theme.body(13, .medium))
                .foregroundStyle(Theme.onAccent)
            if !state.dictateKeys.isEmpty { KeyCaps(keys: state.dictateKeys, onAccent: true) }
            Spacer(minLength: 0)
            BarButton(systemImage: "mic.fill", fill: Theme.accentOnTinta, help: "Ditar sem segurar a tecla", action: state.onDictate)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
    }

    private var recording: some View {
        HStack(spacing: 10) {
            BarButton(systemImage: "xmark", fill: Theme.onAccent.opacity(0.12), help: "Cancelar", action: state.onCancel)
            waveform
            Text(label)
                .font(Theme.body(13, .medium))
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1)
            Spacer(minLength: 0)
            BarButton(systemImage: "stop.fill", fill: Theme.accentOnTinta, help: "Finalizar e colar", action: state.onStop)
        }
        .padding(.horizontal, 6)
    }

    private var busy: some View {
        HStack(spacing: 10) {
            statusIcon
            Text(label)
                .font(Theme.body(13, .medium))
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var statusIcon: some View {
        switch state.phase {
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accentOnTinta)
        case .tip:
            Image(systemName: "text.cursor").foregroundStyle(Theme.onAccent)
        default:
            ProgressView().controlSize(.small).tint(Theme.onAccent)
        }
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(state.phase == .command ? Theme.accentOnTinta : Theme.onAccent)
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: state.level)
    }

    private var label: String {
        switch state.phase {
        case .listening: return "Ouvindo…"
        case .handsFree: return "Mãos livres"
        case .command: return "Diga a instrução…"
        case .thinking: return "Processando…"
        case .transcribing: return "Transcrevendo…"
        case .polishing: return "Ajustando texto…"
        case .transforming(let name): return "\(name)…"
        case .error(let message), .tip(let message): return message
        case .hidden: return ""
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let weights: [CGFloat] = [0.5, 0.8, 1, 0.8, 0.5]
        let level = min(CGFloat(state.level) * 12, 1)
        return 4 + 18 * level * weights[index]
    }
}

private struct BarButton: View {
    let systemImage: String
    let fill: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 26, height: 26)
                // Inset 4–7 pt from the bar's edge, so a smaller radius keeps the corners concentric.
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The microphone choice from Settings, also reachable from the bar's menu.
private struct MicrophoneMenu: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        item("Automático", Microphones.automatic)
        Divider()
        ForEach(Microphones.inputs) { item($0.name, $0.uid) }
    }

    private func item(_ title: String, _ value: String) -> some View {
        Button {
            state.onSelectMicrophone(value)
        } label: {
            if state.microphone == value { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

/// While the bar is dragged: the three places it can dock, with the one it will snap to highlighted.
private final class DockGuideWindow {
    private let panel: NSPanel
    private let model = DockGuideModel()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: DockGuideView(model: model))
    }

    func show(on screen: NSScreen, nearest: DockEdge) {
        let frame = screen.visibleFrame
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        // Each place is drawn the size of the opened bar there, in the window's top-left coordinates.
        model.slots = DockEdge.allCases.map { edge in
            let size = edge == .bottom ? NSSize(width: 168, height: 36) : NSSize(width: 52, height: 112)
            let origin = OverlayWindow.slot(edge, size: size, in: frame)
            return DockGuideModel.Slot(edge: edge, rect: CGRect(x: origin.x - frame.minX, y: frame.maxY - origin.y - size.height,
                                                                  width: size.width, height: size.height))
        }
        model.nearest = nearest
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class DockGuideModel: ObservableObject {
    struct Slot: Identifiable {
        let edge: DockEdge
        let rect: CGRect
        var id: DockEdge { edge }
    }

    @Published var slots: [Slot] = []
    @Published var nearest: DockEdge = .bottom
}

private struct DockGuideView: View {
    @ObservedObject var model: DockGuideModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.slots) { slot in
                let active = slot.edge == model.nearest
                BarView.shape
                    .fill(active ? Theme.accentOnTinta.opacity(0.28) : Color(hex: 0x0A0A0A).opacity(0.18))
                    .overlay(BarView.shape
                        .strokeBorder(active ? Theme.accentOnTinta : Theme.onAccent.opacity(0.6),
                                      style: StrokeStyle(lineWidth: active ? 2 : 1, dash: active ? [] : [4, 3])))
                    .frame(width: slot.rect.width, height: slot.rect.height)
                    .offset(x: slot.rect.minX, y: slot.rect.minY)
                    .animation(.easeOut(duration: 0.12), value: model.nearest)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
