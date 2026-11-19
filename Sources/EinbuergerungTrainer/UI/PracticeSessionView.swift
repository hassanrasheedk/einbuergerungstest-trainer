import SwiftUI

/// A practice run through a list of questions with instant feedback.
/// Questions answered wrong come back once at the end of the run.
struct PracticeSessionView: View {
    let title: String
    let initial: [Question]

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Question] = []
    @State private var index = 0
    @State private var chosen: Int?
    @State private var correct = 0
    @State private var answered = 0
    @State private var requeued: Set<String> = []
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if finished || queue.isEmpty {
                    summary
                } else {
                    question
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(finished || queue.isEmpty ? title : "\(index + 1) von \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Fertig" : "Beenden") { dismiss() }
                }
            }
        }
        .onAppear { if queue.isEmpty { queue = initial } }
    }

    private var question: some View {
        let q = queue[index]
        return VStack(spacing: 0) {
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .tint(.ink)
            ScrollViewReader { proxy in
                ScrollView {
                    QuestionView(question: q, mode: .practice(chosen: chosen)) { i in
                        choose(i, for: q)
                    }
                    .padding(20)
                    .id(q.id)
                }
                .onChange(of: index) { proxy.scrollTo(queue[index].id, anchor: .top) }
            }
            if chosen != nil {
                PrimaryActionBar(action: next) {
                    Text(index + 1 < queue.count ? "Weiter" : "Auswertung")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: chosen != nil)
    }

    private func choose(_ i: Int, for q: Question) {
        guard chosen == nil else { return }
        chosen = i
        answered += 1
        let isRight = i == q.correct
        if isRight { correct += 1 }
        Haptics.answer(correct: isRight)
        store.record(q, chosen: i)
        if !isRight, !requeued.contains(q.id) {
            requeued.insert(q.id)
            queue.append(q)
        }
    }

    private func next() {
        chosen = nil
        if index + 1 < queue.count {
            index += 1
        } else {
            finished = true
        }
    }

    private var summary: some View {
        let reviewed = Array(Set(initial.map(\.id)))
        let qs = reviewed.compactMap { Catalog.byID[$0] }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if answered == 0 {
                        Text("Nichts zu tun")
                            .font(.title2.weight(.bold))
                        Text("In dieser Auswahl gibt es gerade keine Fragen.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(correct) von \(answered) richtig")
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                        Text(requeued.isEmpty
                             ? "Alles auf Anhieb gewusst."
                             : "\(requeued.count) Fragen waren zunächst falsch. Sie kommen in den nächsten Tagen wieder.")
                            .foregroundStyle(.secondary)
                    }
                    MasteryBar(counts: store.masteryCounts(qs))
                    MasteryLegend(counts: store.masteryCounts(qs))
                }
                .padding(.vertical, 8)
            }
            if !requeued.isEmpty {
                Section("Zunächst falsch") {
                    ForEach(queue.filter { requeued.contains($0.id) }.uniqued(), id: \.id) { q in
                        NavigationLink {
                            QuestionDetailView(question: q)
                        } label: {
                            CatalogRow(question: q)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

extension Array where Element == Question {
    func uniqued() -> [Question] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
