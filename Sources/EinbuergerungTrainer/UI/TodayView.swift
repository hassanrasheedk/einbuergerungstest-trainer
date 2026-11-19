import SwiftUI

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: SessionRequest?
    @State private var showExam = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                countdownSection
                planSection
                progressSection
                examSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(countdownTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
            .fullScreenCover(item: $session) { s in PracticeSessionView(title: s.title, initial: s.questions) }
            .fullScreenCover(isPresented: $showExam) { ExamSessionView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: scenePhase) { if scenePhase == .active { store.refreshPlan() } }
        }
    }

    private var countdownSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Einbürgerungstest · \(store.examDate.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                if !store.examDateConfirmed {
                    Button("Testtermin festlegen") { showSettings = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        }
    }

    private var countdownTitle: String {
        switch store.daysUntilExam {
        case ..<0: "Test geschafft?"
        case 0: "Heute ist Testtag"
        case 1: "Morgen ist der Test"
        case let d: "Noch \(d) Tage"
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if let plan = store.plan {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    if plan.allIDs.isEmpty {
                        Text("Heute nichts fällig")
                            .font(.title3.weight(.semibold))
                        Text("Alle Fragen sind gelernt und nichts ist zur Wiederholung fällig. Mach einen Probetest.")
                            .foregroundStyle(Color.secondary)
                    } else if plan.isComplete {
                        Label("Plan für heute erledigt", systemImage: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("\(plan.allIDs.count) Fragen geschafft. Morgen geht es weiter.")
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text(planHeadline(plan))
                            .font(.title3.weight(.semibold))
                        Text(planDetail(plan))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                        ProgressView(value: Double(plan.doneIDs.count), total: Double(plan.allIDs.count))
                            .tint(.ink)
                    }
                    if !plan.remaining.isEmpty {
                        Button {
                            session = SessionRequest(title: "Tagesplan", questions: plan.remaining.compactMap { Catalog.byID[$0] })
                        } label: {
                            Text(plan.doneIDs.isEmpty ? "Lernen starten" : "Weiterlernen")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Tagesplan")
            }
        }
    }

    private func planHeadline(_ plan: DailyPlan) -> String {
        let left = plan.remaining.count
        return left == 1 ? "Noch 1 Frage für heute" : "Noch \(left) Fragen für heute"
    }

    private func planDetail(_ plan: DailyPlan) -> String {
        var parts: [String] = []
        if !plan.newIDs.isEmpty { parts.append("\(plan.newIDs.count) neue") }
        if !plan.reviewIDs.isEmpty { parts.append("\(plan.reviewIDs.count) Wiederholungen") }
        let unseen = store.unseen.count
        let tail = unseen > 0
            ? "Bei diesem Tempo kennst du alle 310 Fragen \(Store.bufferDays) Tage vor dem Test."
            : "Alle Fragen gesehen, jetzt geht es ums Festigen."
        return parts.joined(separator: " · ") + ". " + tail
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                let counts = store.masteryCounts()
                HStack(alignment: .firstTextBaseline) {
                    Text("\(counts[.solid] ?? 0)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("von \(Catalog.all.count) sicher")
                        .foregroundStyle(Color.secondary)
                }
                MasteryBar(counts: counts)
                MasteryLegend(counts: counts)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Fortschritt")
        } footer: {
            Text("Sicher heißt: zweimal hintereinander richtig beantwortet.")
        }
    }

    private var examSection: some View {
        Section {
            Button { showExam = true } label: {
                HStack {
                    Label("Probetest starten", systemImage: "timer")
                    Spacer()
                    Text("33 Fragen · 60 Min")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                .frame(minHeight: 36)
            }
            if let last = store.exams.first {
                HStack {
                    Text("Letzter Probetest")
                    Spacer()
                    Text("\(last.correct)/\(last.total)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(last.passed ? .green : .red)
                }
            }
        } header: {
            Text("Prüfung simulieren")
        }
    }
}

struct SessionRequest: Identifiable {
    let id = UUID()
    let title: String
    let questions: [Question]
}
