import SwiftUI

struct CatalogView: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var topic: String?

    private var results: [Question] {
        Catalog.all.filter { q in
            (topic == nil || q.topic == topic) && matches(q)
        }
    }

    private func matches(_ q: Question) -> Bool {
        let s = search.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return true }
        if let n = Int(s) { return q.number == n }
        return q.question.localizedCaseInsensitiveContains(s)
            || q.answers.contains { $0.localizedCaseInsensitiveContains(s) }
            || q.en.question.localizedCaseInsensitiveContains(s)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { q in
                    NavigationLink {
                        QuestionDetailView(question: q)
                    } label: {
                        CatalogRow(question: q)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Frage, Antwort oder Nummer")
            .navigationTitle("Katalog")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Thema", selection: $topic) {
                            Text("Alle Themen").tag(String?.none)
                            ForEach(Catalog.topics, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        Image(systemName: topic == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Nach Thema filtern")
                }
            }
        }
    }
}

struct CatalogRow: View {
    let question: Question
    var chosen: Int? = nil
    @Environment(Store.self) private var store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(Color.mastery(store.mastery(of: question.id)))
                .frame(width: 8, height: 8)
                .accessibilityLabel(store.mastery(of: question.id).title)
            VStack(alignment: .leading, spacing: 4) {
                Text(question.isState ? "NRW \(question.number)" : "\(question.number)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(question.question)
                    .font(.subheadline)
                    .lineLimit(3)
                if let chosen, chosen != question.correct {
                    answerLine(question.answers[chosen], symbol: "xmark", color: .red)
                }
                answerLine(question.answers[question.correct], symbol: "checkmark", color: .green)
            }
        }
        .padding(.vertical, 4)
    }

    private func answerLine(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption.weight(.bold))
            Text(text).lineLimit(2)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(color)
    }
}

struct QuestionDetailView: View {
    let question: Question

    var body: some View {
        ScrollView {
            QuestionView(question: question, mode: .review(chosen: nil))
                .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(question.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
