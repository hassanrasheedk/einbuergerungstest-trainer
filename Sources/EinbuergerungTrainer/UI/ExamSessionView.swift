import SwiftUI

/// Mock exam: 33 questions, 60 minutes, no feedback until handed in.
struct ExamSessionView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var questions: [Question] = []
    @State private var answers: [String: Int] = [:]
    @State private var index = 0
    @State private var startedAt = Date.now
    @State private var result: ExamResult?
    @State private var showOverview = false
    @State private var confirmSubmit = false
    @State private var confirmQuit = false

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    ExamResultView(result: result, questions: questions, answers: answers)
                } else if !questions.isEmpty {
                    examBody
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(result == nil)
        .onAppear {
            if questions.isEmpty {
                questions = store.makeExam()
                startedAt = .now
            }
        }
        .task(id: result == nil) {
            // Auto-submit when time runs out.
            while result == nil, !Task.isCancelled {
                if Date.now.timeIntervalSince(startedAt) >= ExamRules.duration { submit(); break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if result == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { confirmQuit = true }
                    .confirmationDialog("Probetest abbrechen?", isPresented: $confirmQuit, titleVisibility: .visible) {
                        Button("Abbrechen, nicht werten", role: .destructive) { dismiss() }
                    }
            }
            ToolbarItem(placement: .principal) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, ExamRules.duration - ctx.date.timeIntervalSince(startedAt))
                    Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(left < 300 ? Color.red : Color.primary)
                        .accessibilityLabel("Verbleibende Zeit")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Abgeben") { confirmSubmit = true }
                    .fontWeight(.semibold)
                    .confirmationDialog(submitTitle, isPresented: $confirmSubmit, titleVisibility: .visible) {
                        Button("Jetzt abgeben") { submit() }
                    }
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private var submitTitle: String {
        let open = questions.count - answers.count
        return open == 0 ? "Test abgeben?" : "Noch \(open) Fragen offen. Trotzdem abgeben?"
    }

    private var examBody: some View {
        let q = questions[index]
        return VStack(spacing: 0) {
            ProgressView(value: Double(answers.count), total: Double(questions.count))
                .tint(.ink)
            ScrollView {
                QuestionView(question: q, mode: .exam(chosen: answers[q.id])) { i in
                    answers[q.id] = i
                    Haptics.tap()
                }
                .padding(20)
            }
            .id(q.id)

            HStack(spacing: 12) {
                Button {
                    index -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.secondary)
                .disabled(index == 0)
                .accessibilityLabel("Vorherige Frage")

                Button { showOverview = true } label: {
                    Text("Frage \(index + 1) von \(questions.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.secondary)

                Button {
                    index += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 44, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(index + 1 >= questions.count)
                .accessibilityLabel("Nächste Frage")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(isPresented: $showOverview) { overview.presentationDetents([.medium]) }
    }

    private var overview: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(questions.indices, id: \.self) { i in
                        let done = answers[questions[i].id] != nil
                        Button {
                            index = i
                            showOverview = false
                        } label: {
                            Text("\(i + 1)")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(done ? Color.white : Color.primary)
                                .background(done ? Color.ink : Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    if i == index {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.ink, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Frage \(i + 1), \(done ? "beantwortet" : "offen")")
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("\(answers.count) von \(questions.count) beantwortet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() {
        guard result == nil else { return }
        var correct = 0
        var wrong: [String] = []
        for q in questions {
            if let a = answers[q.id] {
                store.record(q, chosen: a)
                if a == q.correct { correct += 1 } else { wrong.append(q.id) }
            } else {
                wrong.append(q.id)
            }
        }
        let r = ExamResult(date: .now, correct: correct, total: questions.count,
                           duration: Date.now.timeIntervalSince(startedAt), wrongIDs: wrong)
        store.addExam(r)
        Haptics.answer(correct: r.passed)
        result = r
    }
}

struct ExamResultView: View {
    let result: ExamResult
    let questions: [Question]
    let answers: [String: Int]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(result.passed ? "Bestanden" : "Nicht bestanden",
                          systemImage: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(result.passed ? .green : .red)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(shown)")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(shown)))
                        Text("von \(result.total) richtig")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text("Zum Bestehen brauchst du \(ExamRules.passMark). Zeit: \(minutesText(result.duration)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            let wrong = questions.filter { result.wrongIDs.contains($0.id) }
            if !wrong.isEmpty {
                Section("Falsch oder offen (\(wrong.count))") {
                    ForEach(wrong) { q in
                        NavigationLink {
                            ScrollView {
                                QuestionView(question: q, mode: .review(chosen: answers[q.id])).padding(20)
                            }
                            .background(Color(uiColor: .systemGroupedBackground))
                            .navigationTitle(q.label)
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            CatalogRow(question: q, chosen: answers[q.id])
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ergebnis")
        .onAppear {
            if reduceMotion {
                shown = result.correct
            } else {
                withAnimation(.easeOut(duration: 0.6).delay(0.15)) { shown = result.correct }
            }
        }
    }
}
