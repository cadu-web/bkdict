import SwiftUI

/// Meetings: record one, then read its summary and its transcript (Você / Eles).
struct MeetingsView: View {
    @ObservedObject var meetings: MeetingCenter
    @State private var selected: String?

    var body: some View {
        if let id = selected, let meeting = meetings.meetings.first(where: { $0.id == id }) {
            MeetingDetail(meetings: meetings, meeting: meeting) { selected = nil }
        } else {
            list
        }
    }

    private var list: some View {
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "Reuniões",
                           subtitle: "Grava o seu microfone e o áudio do computador, transcreve e resume. Tudo fica neste Mac.")
                Spacer()
                RecordButton(meetings: meetings)
            }
            if meetings.meetings.isEmpty {
                VStack(spacing: 8) {
                    Text("Nenhuma reunião gravada")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.text)
                    Text("Comece a gravar quando a chamada começar. Ao parar, o Bkdict separa o que você disse do que os outros disseram e faz o resumo.")
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(meetings.meetings) { meeting in
                        Button { selected = meeting.id } label: {
                            MeetingRow(meeting: meeting, divider: meeting.id != meetings.meetings.last?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 0)
            }
        }
    }
}

/// Start, or stop with the elapsed time.
private struct RecordButton: View {
    @ObservedObject var meetings: MeetingCenter

    var body: some View {
        if let since = meetings.recordingSince {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        Text(Meeting.clock(context.date.timeIntervalSince(since)))
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.text)
                    }
                }
                Button { meetings.stop() } label: { Label("Parar gravação", systemImage: "stop.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else {
            Button { meetings.start() } label: { Label("Gravar reunião", systemImage: "record.circle") }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let divider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.wave.2")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title).foregroundStyle(Theme.text)
                    Text(meeting.status == .recording ? "Gravando" : Meeting.clock(meeting.duration))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                MeetingStatusLabel(meeting: meeting)
                Image(systemName: "chevron.right").font(Theme.body(11)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            if divider { Divider().overlay(Theme.border).padding(.leading, 50) }
        }
    }
}

private struct MeetingStatusLabel: View {
    let meeting: Meeting

    var body: some View {
        Text(text)
            .font(Theme.mono(10, .medium))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(meeting.status == .failed ? Theme.accent : Theme.secondary)
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
}

private struct MeetingDetail: View {
    @ObservedObject var meetings: MeetingCenter
    let meeting: Meeting
    let back: () -> Void
    @State private var confirmDelete = false
    @State private var copied: String?

    var body: some View {
        Page {
            Button(action: back) { Label("Reuniões", systemImage: "chevron.left") }
                .buttonStyle(.plain)
                .font(Theme.body(13, .medium))
                .foregroundStyle(Theme.accent)

            HStack(alignment: .bottom) {
                PageHeader(title: meeting.title,
                           subtitle: "\(Meeting.clock(meeting.duration)) · \(meeting.segments.count) falas")
                Spacer()
                MeetingStatusLabel(meeting: meeting)
            }

            if let error = meeting.error {
                Notice(text: error)
            } else if meeting.status == .ready && !meeting.systemAudio {
                Notice(text: "Só o seu microfone foi gravado. Para captar os outros, libere o Bkdict em Ajustes do Sistema → Privacidade e Segurança → Gravação de Áudio do Sistema.")
            }

            if meeting.status == .ready || meeting.status == .failed {
                actions
            }

            SectionTitle("Resumo")
            Group {
                if let summary = meeting.summary {
                    MarkdownText(markdown: summary)
                } else {
                    Text(meeting.status == .summarizing ? "Resumindo…" : "O resumo sai depois da transcrição.")
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            SectionTitle("Transcrição")
            Group {
                if meeting.segments.isEmpty {
                    Text(meeting.status == .transcribing ? "Transcrevendo… \(Int(meeting.progress * 100))%" : "Sem falas.")
                        .foregroundStyle(Theme.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(meeting.segments.enumerated()), id: \.offset) { _, segment in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(Meeting.clock(segment.start))
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(width: 44, alignment: .leading)
                                Text(segment.source == .me ? "Você" : "Eles")
                                    .font(Theme.body(13, .semibold))
                                    .foregroundStyle(segment.source == .me ? Theme.accent : Theme.text)
                                    .frame(width: 40, alignment: .leading)
                                Text(segment.text)
                                    .foregroundStyle(Theme.text)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(copied == "summary" ? "Copiado" : "Copiar resumo") {
                copyToClipboard(meeting.summary ?? "")
                flash("summary")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(meeting.summary == nil)
            Button(copied == "transcript" ? "Copiado" : "Copiar transcrição") {
                copyToClipboard(meeting.transcript)
                flash("transcript")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(meeting.segments.isEmpty)
            Button("Refazer resumo") { meetings.resummarize(meeting.id) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(meeting.segments.isEmpty)
            Spacer()
            if confirmDelete {
                Text("Apagar a gravação e a transcrição?").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                Button("Apagar") {
                    meetings.delete(meeting.id)
                    back()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Cancelar") { confirmDelete = false }.buttonStyle(SecondaryButtonStyle())
            } else {
                Button { confirmDelete = true } label: { Label("Apagar", systemImage: "trash") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func flash(_ which: String) {
        copied = which
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == which { copied = nil } }
    }
}

private struct Notice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Theme.accent)
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

/// The small Markdown the summary uses: `## ` headings, `- ` items and plain paragraphs.
private struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    Text(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.text)
                        .padding(.top, index == 0 ? 0 : 8)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("–").foregroundStyle(Theme.accent)
                        inline(String(trimmed.dropFirst(2)))
                    }
                } else if !trimmed.isEmpty {
                    inline(trimmed)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// Bold and italics inside a line.
    private func inline(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}
