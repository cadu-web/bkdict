import EventKit
import AVFoundation
import SwiftUI

/// Meetings: record one, then read its summary and its transcript (Você / Eles).
struct MeetingsView: View {
    @ObservedObject var meetings: MeetingCenter
    @State private var selected: String?
    @State private var startTab = MeetingDetail.Tab.summary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let id = selected, let meeting = meetings.meetings.first(where: { $0.id == id }) {
                MeetingDetail(meetings: meetings, meeting: meeting, startTab: startTab, open: { open($0, tab: .transcript) }) { open(nil) }
                    .id(id + startTab.rawValue)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                MeetingList(meetings: meetings, open: { open($0) }, openTranscript: { open($0, tab: .transcript) })
                    .transition(.opacity)
            }
        }
    }

    private func open(_ id: String?, tab: MeetingDetail.Tab = .summary) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
            startTab = tab
            selected = id
        }
    }
}

// MARK: - List

private struct MeetingList: View {
    @ObservedObject var meetings: MeetingCenter
    let open: (String) -> Void
    let openTranscript: (String) -> Void

    var body: some View {
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "Reuniões",
                           subtitle: "Grava o seu microfone e o áudio do computador, transcreve e resume. Tudo fica neste Mac.")
                Spacer()
                if meetings.recordingSince == nil {
                    Button { meetings.start() } label: { Label("Gravar reunião", systemImage: "record.circle") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            if let since = meetings.recordingSince {
                RecordingBanner(since: since) { meetings.stop() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if meetings.meetings.contains(where: { $0.status == .ready }) {
                AskBox(meetings: meetings, scope: nil, open: openTranscript)
            }
            if meetings.meetings.isEmpty {
                EmptyMeetings()
            } else {
                VStack(spacing: 8) {
                    ForEach(meetings.meetings) { meeting in
                        MeetingCard(meeting: meeting) { open(meeting.id) }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: meetings.recordingSince)
    }
}

private struct RecordingBanner: View {
    let since: Date
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            PulsingDot(size: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("GRAVANDO REUNIÃO")
                    .font(Theme.mono(10, .medium)).tracking(0.8)
                    .foregroundStyle(Theme.accent)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Meeting.clock(context.date.timeIntervalSince(since)))
                        .font(Theme.mono(28, .medium))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                }
            }
            Spacer()
            Text("Seu microfone e o áudio do computador")
                .font(Theme.body(12))
                .foregroundStyle(Theme.secondary)
            Button { stop() } label: { Label("Parar e resumir", systemImage: "stop.fill") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accentTint))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent.opacity(0.35)))
    }
}

private struct EmptyMeetings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text("Nenhuma reunião gravada")
                .font(Theme.display(20))
                .foregroundStyle(Theme.text)
            Text("Comece a gravar quando a chamada começar. Ao parar, o Bkdict separa o que você disse do que os outros disseram e faz o resumo.")
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .card()
    }
}

private struct MeetingCard: View {
    let meeting: Meeting
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DateTile(date: meeting.startedAt)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(Theme.body(14, .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Text(Self.time.string(from: meeting.startedAt))
                        if meeting.status != .recording { Text("·"); Text(Meeting.clock(meeting.duration)) }
                        if meeting.status == .ready, !meeting.segments.isEmpty { Text("·"); Text("\(meeting.segments.count) falas") }
                    }
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
                    if meeting.status == .transcribing {
                        ProgressView(value: meeting.progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .frame(maxWidth: 220)
                            .animation(.easeOut(duration: 0.3), value: meeting.progress)
                    }
                }
                Spacer()
                StatusPill(meeting: meeting)
                Image(systemName: "chevron.right")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.secondary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(hovering ? Theme.hover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Day and month, the way a calendar shows them.
private struct DateTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.day.string(from: date))
                .font(Theme.display(20))
                .foregroundStyle(Theme.accent)
            Text(Self.month.string(from: date).uppercased().replacingOccurrences(of: ".", with: ""))
                .font(Theme.mono(9, .medium)).tracking(0.7)
                .foregroundStyle(Theme.secondary)
        }
        .frame(width: 46, height: 46)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accentTint))
    }

    private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd"; return f }()
    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

private struct StatusPill: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 6) {
            if meeting.status == .recording {
                PulsingDot(size: 7)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text)
                .font(Theme.mono(10, .medium)).tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.hover))
        .animation(.easeOut(duration: 0.2), value: text)
    }

    private var text: String {
        switch meeting.status {
        case .recording: "Gravando"
        case .transcribing: "Transcrevendo \(Int(meeting.progress * 100))%"
        case .separating: "Separando as vozes"
        case .summarizing: "Resumindo"
        case .failed: "Falhou"
        case .ready: meeting.systemAudio ? "Pronta" : "Só o seu microfone"
        }
    }

    private var color: Color {
        switch meeting.status {
        case .ready: meeting.systemAudio ? Theme.ready : Theme.warn
        case .failed: Theme.accent
        default: Theme.warn
        }
    }
}

private struct PulsingDot: View {
    let size: CGFloat
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.25)).frame(width: size * 2, height: size * 2)
                .scaleEffect(on ? 1 : 0.4).opacity(on ? 0 : 1)
            Circle().fill(Theme.accent).frame(width: size, height: size)
        }
        .frame(width: size * 2, height: size * 2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

// MARK: - Detail

private struct MeetingDetail: View {
    enum Tab: String, CaseIterable { case summary = "Resumo", transcript = "Transcrição" }

    @ObservedObject var meetings: MeetingCenter
    let meeting: Meeting
    var startTab = Tab.summary
    /// Opens a meeting (a citation in an answer) on its transcript.
    var open: (String) -> Void = { _ in }
    let back: () -> Void
    @State private var tab = Tab.summary
    @State private var confirmDelete = false
    /// A voice was renamed or merged since the summary was written.
    @State private var renamed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Page {
            Button(action: back) { Label("Reuniões", systemImage: "chevron.left") }
                .buttonStyle(.plain)
                .font(Theme.body(13, .medium))
                .foregroundStyle(Theme.accent)

            header
                .onAppear { tab = startTab }

            if meeting.status == .ready {
                AskBox(meetings: meetings, scope: meeting, open: open)
            }

            if let error = meeting.error {
                Notice(icon: "exclamationmark.triangle", text: error)
            } else if meeting.status == .ready && !meeting.systemAudio {
                Notice(icon: "mic", text: "Só o seu microfone foi gravado. Para captar os outros, libere o Bkdict em Ajustes do Sistema → Privacidade e Segurança → Gravação de Áudio do Sistema.")
            }

            if meeting.status == .recording, let since = meetings.recordingSince {
                RecordingBanner(since: since) { meetings.stop() }
            } else {
                HStack(alignment: .bottom) {
                    TabBar(selection: $tab)
                    Spacer()
                    actions
                }
                Group {
                    switch tab {
                    case .summary: summary
                    case .transcript: transcript
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: meeting.status)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tab)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(meeting.title)
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer()
                StatusPill(meeting: meeting)
            }
            HStack(spacing: 16) {
                Meta(icon: "calendar", text: Self.date.string(from: meeting.startedAt))
                if meeting.status != .recording { Meta(icon: "clock", text: Meeting.clock(meeting.duration)) }
                if !meeting.segments.isEmpty { Meta(icon: "text.bubble", text: "\(meeting.segments.count) falas") }
                Meta(icon: meeting.systemAudio ? "person.2" : "mic", text: meeting.systemAudio ? "Você e os participantes" : "Só o seu microfone")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            CopyButton(help: "Copiar resumo", systemImage: "doc.on.doc", text: meeting.summary ?? "")
                .disabled(meeting.summary == nil)
            CopyButton(help: "Copiar transcrição", systemImage: "text.quote", text: meeting.transcript)
                .disabled(meeting.segments.isEmpty)
            IconButton(help: "Refazer resumo", systemImage: "arrow.clockwise") { meetings.resummarize(meeting.id) }
                .disabled(meeting.segments.isEmpty || meeting.status != .ready && meeting.status != .failed)
            IconButton(help: "Apagar reunião", systemImage: "trash") { confirmDelete = true }
                .confirmationDialog("Apagar esta reunião?", isPresented: $confirmDelete) {
                    Button("Apagar gravação e transcrição", role: .destructive) {
                        meetings.delete(meeting.id)
                        back()
                    }
                } message: {
                    Text("O áudio, a transcrição e o resumo saem deste Mac.")
                }
        }
    }

    // MARK: Summary

    @ViewBuilder private var summary: some View {
        switch meeting.status {
        case .ready, .failed:
            if let text = meeting.summary {
                SummaryView(summary: MeetingSummary(markdown: text), fallback: text, meeting: meeting,
                            toggle: { task, done in meetings.setTask(meeting.id, task, done: done) })
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        default:
            VStack(alignment: .leading, spacing: 14) {
                ProgressLine(meeting: meeting)
                SummarySkeleton()
            }
            .transition(.opacity)
        }
    }

    // MARK: Transcript

    @ViewBuilder private var transcript: some View {
        if meeting.segments.isEmpty {
            if meeting.status == .transcribing {
                VStack(alignment: .leading, spacing: 14) {
                    ProgressLine(meeting: meeting)
                    TranscriptSkeleton()
                }
                .transition(.opacity)
            } else {
                Text("Nenhuma fala foi captada.").foregroundStyle(Theme.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let count = meeting.speakers?.count, count > 0 {
                    VoicesPanel(meetings: meetings, meeting: meeting, renamed: $renamed)
                }
                if renamed && meeting.status == .ready {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                        Text("Os nomes mudaram.").foregroundStyle(Theme.text)
                        Button("Refazer o resumo com os nomes") {
                            meetings.resummarize(meeting.id)
                            renamed = false
                            tab = .summary
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .transition(.opacity)
                }
                Conversation(meeting: meeting) { index, speaker in
                    meetings.setSpeaker(meeting.id, segment: index, to: speaker)
                    renamed = true
                }
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMMM, HH:mm"
        return formatter
    }()
}

/// The two tabs, with an underline that slides between them.
private struct TabBar: View {
    @Binding var selection: MeetingDetail.Tab
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 22) {
            ForEach(MeetingDetail.Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
                } label: {
                    VStack(spacing: 7) {
                        Text(tab.rawValue)
                            .font(Theme.body(14, selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Theme.text : Theme.secondary)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if selection == tab {
                                Rectangle().fill(Theme.accent).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct Meta: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(Theme.body(12))
            .foregroundStyle(Theme.secondary)
            .labelStyle(.titleAndIcon)
    }
}

private struct IconButton: View {
    let help: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? Theme.text : Theme.secondary.opacity(0.5))
                .frame(width: 32, height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(hovering && enabled ? Theme.hover : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// A copy button that confirms with a check for a moment.
private struct CopyButton: View {
    let help: String
    let systemImage: String
    let text: String
    @State private var copied = false

    var body: some View {
        IconButton(help: copied ? "Copiado" : help, systemImage: copied ? "checkmark" : systemImage) {
            copyToClipboard(text)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
        }
    }
}

private struct Notice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accentTint))
    }
}

/// What the meeting is going through, with the percentage while transcribing.
private struct ProgressLine: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(meeting.status == .transcribing
                     ? "Transcrevendo o que cada um disse… \(Int(meeting.progress * 100))%"
                     : meeting.status == .separating ? "Separando as vozes dos participantes…" : "Escrevendo o resumo…")
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: meeting.progress)
            }
            if meeting.status == .transcribing {
                ProgressView(value: meeting.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .animation(.easeOut(duration: 0.3), value: meeting.progress)
            }
        }
    }
}

// MARK: - Summary

/// The summary's four sections, read from the Markdown the model fills in.
struct MeetingSummary {
    struct Task: Hashable {
        let owner: String?
        let text: String

        /// The task as written in the summary, the key for "done".
        var line: String { owner.map { "\($0): \(text)" } ?? text }
    }

    var overview: [String] = []
    var decisions: [String] = []
    var tasks: [Task] = []
    var open: [String] = []

    var isEmpty: Bool { overview.isEmpty && decisions.isEmpty && tasks.isEmpty && open.isEmpty }

    init(markdown: String) {
        enum Section { case overview, decisions, tasks, open, other }
        var section = Section.other
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.lowercased()
                section = title.contains("resumo") ? .overview
                    : title.contains("decis") ? .decisions
                    : title.contains("tarefa") ? .tasks
                    : title.contains("aberto") ? .open : .other
                continue
            }
            let isItem = line.hasPrefix("- ") || line.hasPrefix("* ")
            let text = isItem ? String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) : line
            // "Nenhuma." is how the model says the section is empty.
            if text.lowercased().hasPrefix("nenhum") && text.count < 12 { continue }
            switch section {
            case .overview, .other: overview.append(text)
            case .decisions: decisions.append(text)
            case .open: open.append(text)
            case .tasks:
                if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) <= 16 {
                    let owner = text[..<colon].trimmingCharacters(in: .whitespaces)
                    tasks.append(Task(owner: owner, text: text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
                } else {
                    tasks.append(Task(owner: nil, text: text))
                }
            }
        }
    }
}

private struct SummaryView: View {
    let summary: MeetingSummary
    let fallback: String
    let meeting: Meeting
    let toggle: (String, Bool) -> Void

    var body: some View {
        if summary.isEmpty {
            Text(fallback).foregroundStyle(Theme.text).textSelection(.enabled).card()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !summary.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.overview, id: \.self) { paragraph in
                            Text(inline(paragraph))
                                .font(Theme.body(15))
                                .lineSpacing(4)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 18)
                }

                SummaryBlock(title: "Tarefas", icon: "checklist", empty: summary.tasks.isEmpty,
                             trailing: summary.tasks.isEmpty ? nil : AnyView(TaskActions(meeting: meeting, tasks: summary.tasks))) {
                    ForEach(summary.tasks, id: \.self) { task in
                        let done = (meeting.doneTasks ?? []).contains(task.line)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Button { toggle(task.line, !done) } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(done ? Theme.accent : Color.clear)
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(done ? Theme.accent : Theme.secondary.opacity(0.6), lineWidth: 1.2)
                                    if done {
                                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.onAccent)
                                    }
                                }
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                            .help(done ? "Marcar como não feita" : "Marcar como feita")
                            if let owner = task.owner { OwnerChip(owner: owner).opacity(done ? 0.5 : 1) }
                            Text(inline(task.text))
                                .strikethrough(done)
                                .foregroundStyle(done ? Theme.secondary : Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .animation(.easeOut(duration: 0.15), value: done)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    SummaryBlock(title: "Decisões", icon: "checkmark.seal", empty: summary.decisions.isEmpty) {
                        ForEach(summary.decisions, id: \.self) { Bullet(text: inline($0)) }
                    }
                    SummaryBlock(title: "Pontos em aberto", icon: "questionmark.circle", empty: summary.open.isEmpty) {
                        ForEach(summary.open, id: \.self) { Bullet(text: inline($0)) }
                    }
                }
            }
            .textSelection(.enabled)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct SummaryBlock<Content: View>: View {
    let title: String
    let icon: String
    let empty: Bool
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title.uppercased(), systemImage: icon)
                    .font(Theme.mono(10, .medium)).tracking(0.8)
                    .foregroundStyle(Theme.accent)
                Spacer()
                trailing
            }
            if empty {
                Text("Nenhuma").foregroundStyle(Theme.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

private struct Bullet: View {
    let text: AttributedString

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("–").foregroundStyle(Theme.accent)
            Text(text).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OwnerChip: View {
    let owner: String

    private var isYou: Bool { owner.lowercased().hasPrefix("você") || owner.lowercased().hasPrefix("voce") }

    var body: some View {
        Text(owner)
            .font(Theme.body(11, .semibold))
            .foregroundStyle(isYou ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(isYou ? Theme.accent : Theme.hover))
            .fixedSize()
    }
}

// MARK: - Transcript

/// A discreet color per voice, so the others' bubbles tell people apart. Never the Bordô, which is "Você".
enum VoiceColors {
    static let palette: [Color] = [
        Color(light: 0x4F6577, dark: 0x8FA7BA), Color(light: 0x5E6F4E, dark: 0x9FB38C), Color(light: 0x7A6A4C, dark: 0xC2AE86),
        Color(light: 0x66557A, dark: 0xA996BF), Color(light: 0x4C7470, dark: 0x8BB8B2),
    ]

    static func color(_ speaker: Int?) -> Color {
        guard let speaker else { return Theme.text }
        return palette[speaker % palette.count]
    }
}

/// The transcript as a conversation: what you said on the right, the others on the left, each voice named.
private struct Conversation: View {
    let meeting: Meeting
    /// Moves one of the others' segments to a voice (nil: a new voice).
    let reassign: (Int, Int?) -> Void

    var body: some View {
        let segments = meeting.segments
        VStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let mine = segment.source == .me
                let first = index == 0 || segments[index - 1].source != segment.source || segments[index - 1].speaker != segment.speaker
                let color = mine ? Theme.accent : VoiceColors.color(segment.speaker)
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    if first {
                        HStack(spacing: 6) {
                            Text(meeting.label(for: segment)).font(Theme.body(12, .semibold)).foregroundStyle(color)
                            Text(Meeting.clock(segment.start)).font(Theme.mono(10)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.top, index == 0 ? 0 : 10)
                    }
                    Text(segment.text)
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(mine ? Theme.accentTint : segment.speaker == nil ? Theme.card : color.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                            .strokeBorder(mine ? Color.clear : segment.speaker == nil ? Theme.border : color.opacity(0.35)))
                        .help(Meeting.clock(segment.start))
                        .contextMenu {
                            if !mine, let voices = meeting.speakers, !voices.isEmpty {
                                Menu("Esta fala é de…") {
                                    ForEach(0..<voices.count, id: \.self) { voice in
                                        Button { reassign(index, voice) } label: {
                                            if segment.speaker == voice { Label(meeting.name(of: voice), systemImage: "checkmark") } else { Text(meeting.name(of: voice)) }
                                        }
                                    }
                                    Divider()
                                    Button("Nova voz") { reassign(index, nil) }
                                }
                            }
                        }
                }
                .frame(maxWidth: 560, alignment: mine ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            }
        }
    }
}

/// The voices found on the others' track: hear one, name it, or merge it into another.
private struct VoicesPanel: View {
    @ObservedObject var meetings: MeetingCenter
    let meeting: Meeting
    @Binding var renamed: Bool
    @StateObject private var player = VoicePlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("VOZES", systemImage: "person.wave.2")
                    .font(Theme.mono(10, .medium)).tracking(0.8)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("Ouça cada voz e dê um nome. Duas vozes da mesma pessoa? Junte.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(0..<(meeting.speakers?.count ?? 0), id: \.self) { speaker in
                VoiceRow(meeting: meeting, speaker: speaker, player: player,
                         rename: { name in
                             meetings.rename(meeting.id, speaker: speaker, to: name)
                             renamed = true
                         },
                         merge: { target in
                             player.stop()
                             meetings.merge(meeting.id, speaker: speaker, into: target)
                             renamed = true
                         })
            }
        }
        .card(padding: 16)
        .onDisappear { player.stop() }
    }
}

private struct VoiceRow: View {
    let meeting: Meeting
    let speaker: Int
    @ObservedObject var player: VoicePlayer
    let rename: (String) -> Void
    let merge: (Int) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var count: Int { meeting.segments.filter { $0.speaker == speaker }.count }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(VoiceColors.color(speaker)).frame(width: 10, height: 10)
            Button {
                player.toggle(meeting: meeting, speaker: speaker)
            } label: {
                Image(systemName: player.playing == speaker ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.hover))
            }
            .buttonStyle(.plain)
            .help("Ouvir esta voz")
            TextField("Pessoa \(speaker + 1)", text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(focused ? Theme.accent : Theme.border))
                .frame(maxWidth: 240)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            if let attendees = meeting.attendees, !attendees.isEmpty {
                Menu("Convidados") {
                    ForEach(attendees, id: \.self) { person in
                        Button(person) {
                            name = person
                            rename(person)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Escolher entre os convidados do evento")
            }
            Text(count == 1 ? "1 fala" : "\(count) falas")
                .font(Theme.body(12))
                .foregroundStyle(Theme.secondary)
            Spacer()
            if (meeting.speakers?.count ?? 0) > 1 {
                Menu("Juntar com…") {
                    ForEach(0..<(meeting.speakers?.count ?? 0), id: \.self) { other in
                        if other != speaker { Button(meeting.name(of: other)) { merge(other) } }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .onAppear { name = meeting.speakers.map { speaker < $0.count ? $0[speaker] : "" } ?? "" }
        .onChange(of: meeting.speakers) { _, names in name = names.map { speaker < $0.count ? $0[speaker] : "" } ?? "" }
    }

    private func commit() {
        let current = meeting.speakers.map { speaker < $0.count ? $0[speaker] : "" } ?? ""
        if name.trimmingCharacters(in: .whitespaces) != current { rename(name) }
    }
}

/// Plays up to 6 s of a voice: its longest segment, read from the others' track.
@MainActor
final class VoicePlayer: ObservableObject {
    @Published private(set) var playing: Int?
    private var player: AVAudioPlayer?
    private var finish: DispatchWorkItem?

    func toggle(meeting: Meeting, speaker: Int) {
        if playing == speaker {
            stop()
            return
        }
        stop()
        guard let longest = meeting.segments.filter({ $0.speaker == speaker }).max(by: { $0.end - $0.start < $1.end - $1.start }) else { return }
        let samples = WavFileWriter.samples(in: meeting.systemURL, from: longest.start, to: min(longest.end, longest.start + 6))
        guard let player = try? AVAudioPlayer(data: AudioRecorder.wavData(from: samples)) else { return }
        self.player = player
        player.play()
        playing = speaker
        let done = DispatchWorkItem { [weak self] in self?.playing = nil }
        finish = done
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1, execute: done)
    }

    func stop() {
        finish?.cancel()
        player?.stop()
        player = nil
        playing = nil
    }
}

// MARK: - Skeletons

/// A placeholder bar that breathes while content is being made.
private struct Shimmer: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radius)
            .fill(Theme.secondary.opacity(dim ? 0.10 : 0.22))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

private struct SummarySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Shimmer()
                Shimmer()
                Shimmer(width: 320)
            }
            .card(padding: 18)
            VStack(alignment: .leading, spacing: 12) {
                Shimmer(width: 90, height: 10)
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 10) {
                        Shimmer(width: 13, height: 13)
                        Shimmer(width: 60, height: 16)
                        Shimmer(width: [260, 210, 300][index])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
            HStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        Shimmer(width: 110, height: 10)
                        Shimmer()
                        Shimmer(width: 180)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
                }
            }
        }
    }
}

private struct TranscriptSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { index in
                let mine = index % 2 == 1
                VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                    Shimmer(width: 70, height: 10)
                    Shimmer(width: [340, 260, 300, 220, 360][index], height: 34)
                }
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            }
        }
    }
}

// MARK: - Tasks as actions

/// Copy the tasks as a checklist, send them by e-mail, or turn the open ones into Reminders.
private struct TaskActions: View {
    let meeting: Meeting
    let tasks: [MeetingSummary.Task]
    @State private var note: String?

    private var checklist: String {
        let done = Set(meeting.doneTasks ?? [])
        return tasks.map { "- [\(done.contains($0.line) ? "x" : " ")] \($0.line)" }.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 6) {
            if let note {
                Text(note).font(Theme.body(12)).foregroundStyle(Theme.secondary).transition(.opacity)
            }
            IconButton(help: "Copiar tarefas", systemImage: "doc.on.doc") {
                copyToClipboard(checklist)
                flash("Copiadas")
            }
            IconButton(help: "Enviar por e-mail", systemImage: "envelope") {
                var components = URLComponents()
                components.scheme = "mailto"
                components.queryItems = [URLQueryItem(name: "subject", value: "Tarefas — \(meeting.title)"),
                                         URLQueryItem(name: "body", value: checklist)]
                if let url = components.url { NSWorkspace.shared.open(url) }
            }
            IconButton(help: "Criar lembretes", systemImage: "bell") {
                Task { @MainActor in flash(await Reminders.add(open, from: meeting)) }
            }
        }
        .animation(.easeOut(duration: 0.2), value: note)
    }

    private var open: [String] {
        let done = Set(meeting.doneTasks ?? [])
        return tasks.map(\.line).filter { !done.contains($0) }
    }

    private func flash(_ text: String) {
        note = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if note == text { note = nil } }
    }
}

/// One reminder per open task, in the Reminders app's default list.
enum Reminders {
    @MainActor
    static func add(_ tasks: [String], from meeting: Meeting) async -> String {
        guard !tasks.isEmpty else { return "Nenhuma tarefa aberta" }
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true,
              let list = store.defaultCalendarForNewReminders() else {
            return "Sem acesso aos Lembretes"
        }
        var created = 0
        for task in tasks {
            let reminder = EKReminder(eventStore: store)
            reminder.title = task
            reminder.notes = meeting.title
            reminder.calendar = list
            if (try? store.save(reminder, commit: false)) != nil { created += 1 }
        }
        try? store.commit()
        return created == 1 ? "1 lembrete criado" : "\(created) lembretes criados"
    }
}

// MARK: - Ask

/// A question about the meetings (or one meeting), answered by the AI from a local search of the transcripts.
private struct AskBox: View {
    @ObservedObject var meetings: MeetingCenter
    let scope: Meeting?
    let open: (String) -> Void
    @State private var question = ""
    @State private var answer: String?
    @State private var asking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.accent)
                TextField(scope == nil ? "Pergunte sobre as suas reuniões" : "Pergunte sobre esta reunião", text: $question)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(ask)
                if asking {
                    ProgressView().controlSize(.small)
                } else if !question.isEmpty {
                    Button(action: ask) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .help("Perguntar")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(focused ? Theme.accent : Theme.border))

            if asking {
                VStack(alignment: .leading, spacing: 8) {
                    Shimmer()
                    Shimmer(width: 360)
                }
                .card(padding: 14)
                .transition(.opacity)
            } else if let answer {
                Text(linked(answer))
                    .font(Theme.body(14))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "bkdict", let id = url.host else { return .systemAction }
                        open(id)
                        return .handled
                    })
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: asking)
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !asking else { return }
        asking = true
        let pool = scope.map { [$0] } ?? meetings.meetings
        Task { @MainActor in
            let context = MeetingSearch.context(for: text, in: pool)
            do {
                answer = try await LLM.askMeetings(text, context: context)
            } catch {
                answer = "Não foi possível responder: \(error.localizedDescription). Confira a IA em Modelos."
            }
            asking = false
        }
    }

    /// Turns each [título · mm:ss] citation into a link that opens that meeting's transcript.
    private func linked(_ text: String) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        let pattern = #/\[([^\]\n]+?) · (\d{1,2}:\d{2}(?::\d{2})?)\]/#
        while let match = rest.firstMatch(of: pattern) {
            result += AttributedString(String(rest[..<match.range.lowerBound]))
            var citation = AttributedString("[\(match.1) · \(match.2)]")
            if let meeting = meetings.meetings.first(where: { $0.title == String(match.1) }) {
                citation.link = URL(string: "bkdict://\(meeting.id)")
                citation.underlineStyle = .single
            }
            result += citation
            rest = rest[match.range.upperBound...]
        }
        result += AttributedString(String(rest))
        return result
    }
}
