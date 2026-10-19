import SwiftUI

/// Meetings: record one, then read its summary and its transcript (Você / Eles).
struct MeetingsView: View {
    @ObservedObject var meetings: MeetingCenter
    @State private var selected: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let id = selected, let meeting = meetings.meetings.first(where: { $0.id == id }) {
                MeetingDetail(meetings: meetings, meeting: meeting) { open(nil) }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                MeetingList(meetings: meetings, open: open)
                    .transition(.opacity)
            }
        }
    }

    private func open(_ id: String?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) { selected = id }
    }
}

// MARK: - List

private struct MeetingList: View {
    @ObservedObject var meetings: MeetingCenter
    let open: (String) -> Void

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
    let back: () -> Void
    @State private var tab = Tab.summary
    @State private var confirmDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Page {
            Button(action: back) { Label("Reuniões", systemImage: "chevron.left") }
                .buttonStyle(.plain)
                .font(Theme.body(13, .medium))
                .foregroundStyle(Theme.accent)

            header

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
                SummaryView(summary: MeetingSummary(markdown: text), fallback: text)
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
            Conversation(segments: meeting.segments)
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
                     : "Escrevendo o resumo…")
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

                SummaryBlock(title: "Tarefas", icon: "checklist", empty: summary.tasks.isEmpty) {
                    ForEach(summary.tasks, id: \.self) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.secondary.opacity(0.6), lineWidth: 1.2)
                                .frame(width: 13, height: 13)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                            if let owner = task.owner { OwnerChip(owner: owner) }
                            Text(inline(task.text))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: icon)
                .font(Theme.mono(10, .medium)).tracking(0.8)
                .foregroundStyle(Theme.accent)
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

/// The transcript as a conversation: what you said on the right, the others on the left.
private struct Conversation: View {
    let segments: [Meeting.Segment]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let mine = segment.source == .me
                let first = index == 0 || segments[index - 1].source != segment.source
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    if first {
                        HStack(spacing: 6) {
                            Text(mine ? "Você" : "Eles").font(Theme.body(12, .semibold))
                                .foregroundStyle(mine ? Theme.accent : Theme.text)
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
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(mine ? Theme.accentTint : Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(mine ? Color.clear : Theme.border))
                        .help(Meeting.clock(segment.start))
                }
                .frame(maxWidth: 560, alignment: mine ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            }
        }
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
