import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    var showHistory: () -> Void
    var showModels: () -> Void

    var body: some View {
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "Início")
                Spacer()
                HStack(spacing: 8) {
                    StatPill(icon: "flame.fill", value: "\(model.streakDays)", label: model.streakDays == 1 ? "dia" : "dias")
                    StatPill(icon: "text.word.spacing", value: model.totalWords.formatted(.number.notation(.compactName)), label: "palavras")
                    StatPill(icon: "bolt.fill", value: "\(model.wordsPerMinute)", label: "ppm")
                }
            }

            Hero(model: model, showModels: showModels)

            if !model.accessibilityGranted || !model.microphoneGranted {
                PermissionsCard(model: model)
            }

            if model.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(Theme.body(26))
                        .foregroundStyle(Theme.accent)
                    Text("Nenhum ditado ainda")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.text)
                    Text("Segure \(model.dictateLabel) em qualquer app e comece a falar.")
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .card()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    DictationTimeline(model: model, items: Array(model.history.prefix(30)))
                    if model.history.count > 30 {
                        Button("Ver histórico completo", action: showHistory)
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

private struct Hero: View {
    @ObservedObject var model: AppModel
    var showModels: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                (Text("Segure ") + Text(model.dictateLabel).italic() + Text(" e fale"))
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.onAccent)
                Text("Em qualquer app: o Bkdict transcreve, ajusta a pontuação e insere o texto na posição do cursor.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.onAccent.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 14) {
                    HeroHint(keys: model.keys(for: .handsFree), label: "Mãos livres")
                    HeroHint(keys: model.keys(for: .command), label: "Comando")
                    if let transform = model.shortcut(for: 0) {
                        HeroHint(keys: transform.keys, label: "Transforms")
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(Theme.onAccent.opacity(model.isReady ? 1 : 0.35)).frame(width: 7, height: 7)
                    Text(model.status).font(Theme.body(12, .medium))
                    if !model.isReady {
                        Button("Abrir Modelos", action: showModels)
                            .buttonStyle(.plain)
                            .font(Theme.body(12, .semibold))
                            .underline()
                    }
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(hex: 0x0A0A0A).opacity(0.25)))
            }
            Spacer(minLength: 0)
            BrandMark()
                .fill(Theme.onAccent)
                .frame(width: 150, height: 130)
        }
        .padding(28)
        .background(Theme.hero)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

private struct HeroHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            KeyCaps(keys: keys, onAccent: true)
            Text(label).font(Theme.body(12, .medium)).foregroundStyle(Theme.onAccent.opacity(0.9))
        }
        .fixedSize()
    }
}

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(Theme.body(11)).foregroundStyle(Theme.accent)
            Text(value).font(Theme.body(13, .semibold)).foregroundStyle(Theme.text)
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
        .fixedSize()
    }
}

struct PermissionsCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Permissões pendentes", systemImage: "exclamationmark.shield.fill")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(.orange)
                .padding(16)
            Divider().overlay(Theme.border)
            if !model.accessibilityGranted {
                PermissionRow(title: "Acessibilidade", detail: "Para detectar a tecla e colar o texto",
                              granted: false, divider: !model.microphoneGranted, action: model.openAccessibilitySettings)
            }
            if !model.microphoneGranted {
                PermissionRow(title: "Microfone", detail: "Para ouvir o que você dita",
                              granted: false, divider: false, action: model.requestMicrophone)
            }
        }
        .card(padding: 0)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var divider = true
    let action: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail, divider: divider) {
            if granted {
                Label("Liberado", systemImage: "checkmark.circle.fill")
                    .font(Theme.body(12, .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Liberar", action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""

    private var filtered: [Dictation] {
        query.isEmpty ? model.history : model.history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "Histórico", subtitle: "Tudo o que você ditou, guardado só neste Mac.")
                Spacer()
                if !model.history.isEmpty {
                    Button { model.clearHistory() } label: { Label("Limpar", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            if model.history.isEmpty {
                Text("Nenhum ditado ainda. Segure \(model.dictateLabel) em qualquer app para começar.")
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .card()
            } else {
                SearchField(prompt: "Buscar no histórico", text: $query)
                if filtered.isEmpty {
                    Text("Nada encontrado para \u{201C}\(query)\u{201D}.").foregroundStyle(Theme.secondary)
                } else {
                    DictationTimeline(model: model, items: filtered)
                }
            }
        }
    }
}

/// Dictations grouped by day (Hoje, Ontem, 12 de outubro…).
struct DictationTimeline: View {
    @ObservedObject var model: AppModel
    let items: [Dictation]

    private var days: [(title: String, items: [Dictation])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (Self.title(for: day), grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(days, id: \.title) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.title.uppercased())
                        .font(Theme.mono(11, .medium))
                        .tracking(0.88)
                        .foregroundStyle(Theme.secondary)
                        .padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(day.items) { item in
                            DictationRow(item: item, divider: item.id != day.items.last?.id) {
                                model.delete(item)
                            }
                        }
                    }
                    .card(padding: 0)
                }
            }
        }
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoje" }
        if calendar.isDateInYesterday(day) { return "Ontem" }
        return day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "pt_BR")))
    }
}

private struct DictationRow: View {
    let item: Dictation
    let divider: Bool
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(item.date, format: .dateTime.hour().minute())
                    .font(Theme.body(12).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 48, alignment: .leading)
                Text(item.text)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Button {
                        copyToClipboard(item.text)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copiar")
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help("Apagar")
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.accent : Theme.secondary)
                .opacity(hovering || copied ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hovering ? Theme.hover : .clear)
            if divider { Divider().overlay(Theme.border).padding(.leading, 80) }
        }
        .onHover { hovering = $0 }
    }
}
