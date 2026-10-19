import Foundation

/// Picks what the AI reads to answer a question about meetings: a local word search before any AI (phase 4).
enum MeetingSearch {
    /// Common Portuguese words that say nothing about which meeting is meant.
    private static let stopwords: Set<String> = [
        "de", "da", "do", "das", "dos", "que", "para", "com", "uma", "por", "mas", "foi", "ser", "tem", "como",
        "sobre", "isso", "essa", "esse", "quem", "qual", "quando", "onde", "reuniao", "reunioes",
    ]

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    /// The context for the question, up to 8,000 characters: for the 3 meetings with the most hits (or the 3 most
    /// recent, summaries only, when nothing matches), the title, date, summary and matching lines with a line of
    /// context on each side.
    static func context(for question: String, in meetings: [Meeting]) -> String {
        let terms = Set(words(question))
        let usable = meetings.filter { $0.status == .ready }
        let scored = usable.map { meeting -> (Meeting, Int) in
            let haystack = words([meeting.title, meeting.summary ?? "", meeting.transcript].joined(separator: " "))
            return (meeting, haystack.filter(terms.contains).count)
        }
        let hits = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        let chosen = hits.isEmpty ? Array(usable.prefix(3)) : hits
        let dates = DateFormatter()
        dates.locale = Locale(identifier: "pt_BR")
        dates.dateFormat = "dd/MM/yyyy HH:mm"

        var blocks: [String] = []
        for meeting in chosen {
            var block = "### \(meeting.title) (\(dates.string(from: meeting.startedAt)))\n"
            if let summary = meeting.summary { block += summary + "\n" }
            if !hits.isEmpty {
                let lines = meeting.segments.map { "[\(Meeting.clock($0.start))] \(meeting.label(for: $0)): \($0.text)" }
                var keep = Set<Int>()
                for (index, segment) in meeting.segments.enumerated() where !Set(words(segment.text)).isDisjoint(with: terms) {
                    keep.formUnion(max(0, index - 1)...min(lines.count - 1, index + 1))
                }
                if !keep.isEmpty { block += "Falas:\n" + keep.sorted().map { lines[$0] }.joined(separator: "\n") + "\n" }
            }
            blocks.append(block)
        }
        return String(blocks.joined(separator: "\n").prefix(8_000))
    }
}
