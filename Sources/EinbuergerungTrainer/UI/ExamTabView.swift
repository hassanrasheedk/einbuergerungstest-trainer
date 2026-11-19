import SwiftUI

struct ExamTabView: View {
    @Environment(Store.self) private var store
    @State private var showExam = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Wie im echten Test")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 8) {
                            fact("list.number", "33 Fragen: 30 allgemein, 3 zu NRW")
                            fact("timer", "60 Minuten")
                            fact("checkmark.seal", "Bestanden ab \(ExamRules.passMark) richtigen Antworten")
                            fact("eye.slash", "Auflösung erst nach dem Abgeben")
                        }
                        .font(.subheadline)
                        Button { showExam = true } label: {
                            Text("Probetest starten")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(.vertical, 8)
                }

                if !store.exams.isEmpty {
                    Section {
                        ForEach(store.exams) { r in
                            HStack {
                                Image(systemName: r.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                                    .foregroundStyle(r.passed ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.date.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute().locale(Locale(identifier: "de_DE"))))
                                    Text(minutesText(r.duration))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(r.correct)/\(r.total)")
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                        }
                    } header: {
                        Text("Bisherige Probetests")
                    } footer: {
                        let passed = store.exams.filter(\.passed).count
                        Text("\(passed) von \(store.exams.count) bestanden.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Prüfung")
            .fullScreenCover(isPresented: $showExam) { ExamSessionView() }
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.ink)
        }
    }
}
