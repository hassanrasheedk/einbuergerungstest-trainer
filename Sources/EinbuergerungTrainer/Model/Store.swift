import Foundation
import Observation

/// How well a single question is known.
enum Mastery: Int, CaseIterable, Sendable {
    case new, shaky, learning, solid

    var title: String {
        switch self {
        case .new: "Neu"
        case .shaky: "Wackelig"
        case .learning: "Gelernt"
        case .solid: "Sicher"
        }
    }
}

struct QuestionProgress: Codable, Sendable {
    var box = 0              // Leitner box 0…4
    var seen = 0
    var correctCount = 0
    var wrongCount = 0
    var lastWasWrong = false
    var due: Date?
    var bookmarked = false

    var mastery: Mastery {
        if seen == 0 { return .new }
        if lastWasWrong { return .shaky }
        return box >= 2 ? .solid : .learning
    }
}

struct ExamResult: Codable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var correct: Int
    var total: Int
    var duration: TimeInterval
    var wrongIDs: [String]

    var passed: Bool { correct >= ExamRules.passMark }
}

enum ExamRules {
    static let general = 30
    static let state = 3
    static var total: Int { general + state }
    static let passMark = 17
    static let duration: TimeInterval = 60 * 60
}

struct DailyPlan: Codable, Sendable {
    var day: Date            // start of day
    var newIDs: [String]
    var reviewIDs: [String]
    var doneIDs: Set<String> = []

    var allIDs: [String] { reviewIDs + newIDs }
    var remaining: [String] { allIDs.filter { !doneIDs.contains($0) } }
    var isComplete: Bool { !allIDs.isEmpty && remaining.isEmpty }
}

@MainActor
@Observable
final class Store {
    private struct Saved: Codable {
        var progress: [String: QuestionProgress] = [:]
        var exams: [ExamResult] = []
        var plan: DailyPlan?
        var examDate: Date?
        var examDateConfirmed: Bool?
    }

    private(set) var progress: [String: QuestionProgress] = [:]
    private(set) var exams: [ExamResult] = []
    private(set) var plan: DailyPlan?
    var examDate: Date { didSet { examDateConfirmed = true; save(); plan = nil; refreshPlan() } }
    /// False until the user picks their real test date in Settings.
    private(set) var examDateConfirmed = false

    /// Days of slack kept before the test for pure review.
    static let bufferDays = 2
    /// Leitner intervals in days for boxes 0…4.
    private static let intervals = [0, 1, 2, 4, 7]

    private let url: URL
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.timeZone = .current
        return c
    }

    /// Placeholder until the user sets their test date: four weeks from today, 9:00.
    static var defaultExamDate: Date {
        let cal = Calendar(identifier: .gregorian)
        let inFourWeeks = cal.date(byAdding: .day, value: 28, to: cal.startOfDay(for: .now)) ?? .now
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: inFourWeeks) ?? inFourWeeks
    }

    init(fileName: String = "progress.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(fileName)
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
        progress = saved.progress
        exams = saved.exams
        plan = saved.plan
        examDate = saved.examDate ?? Store.defaultExamDate
        // Installs from before this flag existed already had a real date stored.
        examDateConfirmed = saved.examDateConfirmed ?? (saved.examDate != nil)
        refreshPlan()
    }

    private func save() {
        let saved = Saved(progress: progress, exams: exams, plan: plan,
                          examDate: examDate, examDateConfirmed: examDateConfirmed)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Queries

    func progress(for id: String) -> QuestionProgress { progress[id] ?? QuestionProgress() }
    func mastery(of id: String) -> Mastery { progress(for: id).mastery }

    func count(_ mastery: Mastery, in questions: [Question] = Catalog.all) -> Int {
        questions.reduce(0) { $0 + (self.mastery(of: $1.id) == mastery ? 1 : 0) }
    }

    var daysUntilExam: Int {
        let from = calendar.startOfDay(for: .now)
        let to = calendar.startOfDay(for: examDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    var mistakes: [Question] { Catalog.all.filter { mastery(of: $0.id) == .shaky } }
    var bookmarked: [Question] { Catalog.all.filter { progress(for: $0.id).bookmarked } }
    var unseen: [Question] { Catalog.all.filter { progress(for: $0.id).seen == 0 } }

    // MARK: Daily plan

    /// Builds today's plan once per day: due reviews + an even share of unseen questions.
    func refreshPlan() {
        let today = calendar.startOfDay(for: .now)
        if let plan, calendar.isDate(plan.day, inSameDayAs: today) { return }

        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let reviews = Catalog.all
            .filter { q in
                let p = progress(for: q.id)
                return p.seen > 0 && (p.lastWasWrong || (p.due ?? .distantFuture) < endOfToday)
            }
            .sorted { lhs, rhs in
                let l = progress(for: lhs.id), r = progress(for: rhs.id)
                if l.lastWasWrong != r.lastWasWrong { return l.lastWasWrong }
                return (l.due ?? .distantPast) < (r.due ?? .distantPast)
            }
            .prefix(60)
            .map(\.id)

        let unseen = self.unseen
        let learningDays = max(1, daysUntilExam - Store.bufferDays)
        let share = Int((Double(unseen.count) / Double(learningDays)).rounded(.up))
        let newCount = min(unseen.count, max(share, unseen.isEmpty ? 0 : 15))
        let newIDs = unseen.prefix(newCount).map(\.id)

        plan = DailyPlan(day: today, newIDs: Array(newIDs), reviewIDs: Array(reviews))
        save()
    }

    // MARK: Recording

    func record(_ question: Question, chosen: Int, countsForPlan: Bool = true) {
        var p = progress(for: question.id)
        p.seen += 1
        if chosen == question.correct {
            p.correctCount += 1
            p.box = p.lastWasWrong ? 1 : min(p.box + 1, Store.intervals.count - 1)
            p.lastWasWrong = false
        } else {
            p.wrongCount += 1
            p.box = 0
            p.lastWasWrong = true
        }
        let start = calendar.startOfDay(for: .now)
        p.due = calendar.date(byAdding: .day, value: Store.intervals[p.box], to: start)
        progress[question.id] = p
        if countsForPlan, plan?.allIDs.contains(question.id) == true {
            plan?.doneIDs.insert(question.id)
        }
        save()
    }

    func toggleBookmark(_ id: String) {
        var p = progress(for: id)
        p.bookmarked.toggle()
        progress[id] = p
        save()
    }

    func addExam(_ result: ExamResult) {
        exams.insert(result, at: 0)
        save()
    }

    func resetAll() {
        progress = [:]
        exams = []
        plan = nil
        save()
        refreshPlan()
    }

    /// 30 random general + 3 random NRW questions, NRW last as in the real test.
    func makeExam() -> [Question] {
        Array(Catalog.general.shuffled().prefix(ExamRules.general))
            .sorted { $0.number < $1.number }
            + Array(Catalog.state.shuffled().prefix(ExamRules.state)).sorted { $0.number < $1.number }
    }
}
