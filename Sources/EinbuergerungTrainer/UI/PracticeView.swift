import SwiftUI

struct PracticeView: View {
    @Environment(Store.self) private var store
    @State private var session: SessionRequest?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    focusRow("Fehler wiederholen", symbol: "arrow.uturn.backward.circle", tint: .orange,
                             questions: store.mistakes.shuffled(),
                             empty: "Keine offenen Fehler")
                    focusRow("Markierte Fragen", symbol: "bookmark", tint: .ink,
                             questions: store.bookmarked,
                             empty: "Nichts markiert")
                    focusRow("Noch nie gesehen", symbol: "sparkles", tint: .ink,
                             questions: store.unseen,
                             empty: "Alle Fragen gesehen")
                    focusRow("Zufällige 20", symbol: "shuffle", tint: .ink,
                             questions: Array(Catalog.all.shuffled().prefix(20)),
                             empty: "")
                } header: {
                    Text("Schwerpunkte")
                }

                Section("Themen") {
                    ForEach(Catalog.topics, id: \.self) { topic in
                        let qs = Catalog.all.filter { $0.topic == topic }
                        Button {
                            session = SessionRequest(title: topic, questions: prioritized(qs))
                        } label: {
                            GroupRow(title: topic, symbol: Catalog.symbol(for: topic), questions: qs)
                        }
                    }
                }

                Section {
                    ForEach(0..<10, id: \.self) { block in
                        let from = block * 30 + 1, to = block * 30 + 30
                        let qs = Catalog.general.filter { (from...to).contains($0.number) }
                        Button {
                            session = SessionRequest(title: "Aufgaben \(from)–\(to)", questions: qs)
                        } label: {
                            GroupRow(title: "Aufgaben \(from)–\(to)", symbol: nil, questions: qs)
                        }
                    }
                    Button {
                        session = SessionRequest(title: "Nordrhein-Westfalen", questions: Catalog.state)
                    } label: {
                        GroupRow(title: "NRW 1–10", symbol: nil, questions: Catalog.state)
                    }
                } header: {
                    Text("Der Reihe nach")
                } footer: {
                    Text("Reihenfolge und Wortlaut wie im offiziellen Fragenkatalog des BAMF (Stand 07.05.2025).")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Üben")
            .fullScreenCover(item: $session) { s in PracticeSessionView(title: s.title, initial: s.questions) }
        }
    }

    /// Weakest first: wrong, then new, then learning, then solid.
    private func prioritized(_ qs: [Question]) -> [Question] {
        let rank: [Mastery: Int] = [.shaky: 0, .new: 1, .learning: 2, .solid: 3]
        return qs.sorted { (rank[store.mastery(of: $0.id)]!, $0.order) < (rank[store.mastery(of: $1.id)]!, $1.order) }
    }

    @ViewBuilder
    private func focusRow(_ title: String, symbol: String, tint: Color, questions: [Question], empty: String) -> some View {
        Button {
            session = SessionRequest(title: title, questions: questions)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(questions.isEmpty ? Color.secondary : tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(questions.isEmpty ? Color.secondary : Color.primary)
                    if questions.isEmpty, !empty.isEmpty {
                        Text(empty).font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                if !questions.isEmpty, title != "Zufällige 20" {
                    Text("\(questions.count)")
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(minHeight: 36)
        }
        .disabled(questions.isEmpty)
    }
}

struct GroupRow: View {
    let title: String
    let symbol: String?
    let questions: [Question]
    @Environment(Store.self) private var store

    var body: some View {
        let counts = store.masteryCounts(questions)
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(title).foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(counts[.solid] ?? 0)/\(questions.count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                }
                MasteryBar(counts: counts, height: 5)
            }
        }
        .padding(.vertical, 4)
    }
}
