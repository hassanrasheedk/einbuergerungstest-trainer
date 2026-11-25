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
    /// When this question was last answered or bookmarked; used to merge devices.
    var updatedAt: Date?

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
        var settingsUpdatedAt: Double?
        var resetAt: Double?
        var syncCode: String?
        var lastSync: Date?
    }

    private(set) var progress: [String: QuestionProgress] = [:]
    private(set) var exams: [ExamResult] = []
    private(set) var plan: DailyPlan?
    var examDate: Date {
        didSet {
            guard !applyingRemote else { return }
            examDateConfirmed = true
            settingsUpdatedAt = Date.now.timeIntervalSince1970 * 1000
            save(); plan = nil; refreshPlan(); scheduleSync(after: 0)
        }
    }
    /// False until the user picks their real test date in Settings.
    private(set) var examDateConfirmed = false

    // Sync state (see web/worker.js for the server-side merge).
    private(set) var syncCode: String?
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var syncError: String?
    private var settingsUpdatedAt: Double = 0
    private var resetAt: Double = 0
    private var applyingRemote = false
    private var syncTask: Task<Void, Never>?

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
        settingsUpdatedAt = saved.settingsUpdatedAt ?? 0
        resetAt = saved.resetAt ?? 0
        syncCode = saved.syncCode
        lastSync = saved.lastSync
        refreshPlan()
    }

    private func save() {
        let saved = Saved(progress: progress, exams: exams, plan: plan,
                          examDate: examDate, examDateConfirmed: examDateConfirmed,
                          settingsUpdatedAt: settingsUpdatedAt, resetAt: resetAt,
                          syncCode: syncCode, lastSync: lastSync)
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
        p.updatedAt = .now
        progress[question.id] = p
        if countsForPlan, plan?.allIDs.contains(question.id) == true {
            plan?.doneIDs.insert(question.id)
        }
        save()
        scheduleSync()
    }

    func toggleBookmark(_ id: String) {
        var p = progress(for: id)
        p.bookmarked.toggle()
        p.updatedAt = .now
        progress[id] = p
        save()
        scheduleSync()
    }

    func addExam(_ result: ExamResult) {
        exams.insert(result, at: 0)
        save()
        scheduleSync(after: 0)
    }

    func resetAll() {
        progress = [:]
        exams = []
        plan = nil
        resetAt = Date.now.timeIntervalSince1970 * 1000
        save()
        refreshPlan()
        scheduleSync(after: 0)
    }

    /// 30 random general + 3 random NRW questions, NRW last as in the real test.
    func makeExam() -> [Question] {
        Array(Catalog.general.shuffled().prefix(ExamRules.general))
            .sorted { $0.number < $1.number }
            + Array(Catalog.state.shuffled().prefix(ExamRules.state)).sorted { $0.number < $1.number }
    }

    // MARK: Sync

    static let syncURL = URL(string: "https://einbuergerungstest-trainer.retromoon.workers.dev/api/sync/")!
    private static let codeAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func normalizeCode(_ s: String) -> String {
        String(s.uppercased().filter { codeAlphabet.contains($0) })
    }

    static func prettyCode(_ c: String) -> String {
        stride(from: 0, to: c.count, by: 5).map { i in
            let a = c.index(c.startIndex, offsetBy: i)
            return String(c[a..<c.index(a, offsetBy: min(5, c.count - i))])
        }.joined(separator: "-")
    }

    func createSyncCode() {
        var rng = SystemRandomNumberGenerator()
        syncCode = String((0..<20).map { _ in Store.codeAlphabet[Int(rng.next() & 31)] })
        save()
        scheduleSync(after: 0)
    }

    /// Returns false when the code is not 20 valid characters.
    func joinSync(code: String) -> Bool {
        let c = Store.normalizeCode(code)
        guard c.count == 20 else { return false }
        syncCode = c
        syncError = nil
        save()
        scheduleSync(after: 0)
        return true
    }

    func leaveSync() {
        syncTask?.cancel()
        syncCode = nil
        lastSync = nil
        syncError = nil
        save()
    }

    /// Debounced so a run of answers becomes one request.
    func scheduleSync(after seconds: Double = 2.5) {
        guard syncCode != nil else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let code = syncCode, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var request = URLRequest(url: Store.syncURL.appendingPathComponent(code))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.timeoutInterval = 20
            request.httpBody = try JSONEncoder().encode(syncPayload())
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let merged = try JSONDecoder().decode(SyncState.self, from: data)
            guard syncCode == code else { return }   // left sync meanwhile
            apply(merged)
            syncError = nil
        } catch is CancellationError {
        } catch {
            syncError = (error as? URLError)?.code == .notConnectedToInternet ? "Offline" : "Synchronisierung fehlgeschlagen"
        }
    }

    private func syncPayload() -> SyncState {
        SyncState(
            v: 1,
            progress: progress.mapValues { p in
                SyncState.Progress(box: p.box, seen: p.seen, correct: p.correctCount, wrong: p.wrongCount,
                                   lastWrong: p.lastWasWrong, due: p.due.map { $0.timeIntervalSince1970 * 1000 },
                                   bookmarked: p.bookmarked,
                                   updatedAt: (p.updatedAt?.timeIntervalSince1970 ?? 0) * 1000)
            },
            exams: exams.map { e in
                SyncState.Exam(id: e.id.uuidString, date: SyncState.iso(e.date), correct: e.correct,
                               total: e.total, duration: e.duration, wrongIds: e.wrongIDs)
            },
            plan: plan.map { SyncState.Plan(day: dayKey($0.day), newIds: $0.newIDs, reviewIds: $0.reviewIDs, done: Array($0.doneIDs)) },
            examDate: SyncState.iso(examDate),
            examDateConfirmed: examDateConfirmed,
            settingsUpdatedAt: settingsUpdatedAt,
            resetAt: resetAt
        )
    }

    private func apply(_ m: SyncState) {
        applyingRemote = true
        defer { applyingRemote = false }
        progress = m.progress.mapValues { p in
            QuestionProgress(box: p.box, seen: p.seen, correctCount: p.correct, wrongCount: p.wrong,
                             lastWasWrong: p.lastWrong, due: p.due.map { Date(timeIntervalSince1970: $0 / 1000) },
                             bookmarked: p.bookmarked,
                             updatedAt: p.updatedAt > 0 ? Date(timeIntervalSince1970: p.updatedAt / 1000) : nil)
        }
        exams = m.exams.map { e in
            ExamResult(id: UUID(uuidString: e.id) ?? UUID(), date: SyncState.date(e.date) ?? .now,
                       correct: e.correct, total: e.total, duration: e.duration, wrongIDs: e.wrongIds)
        }
        if let p = m.plan, p.day == dayKey(.now) {
            plan = DailyPlan(day: calendar.startOfDay(for: .now), newIDs: p.newIds, reviewIDs: p.reviewIds, doneIDs: Set(p.done))
        }
        if let s = m.examDate, let d = SyncState.date(s) {
            examDate = d
            examDateConfirmed = m.examDateConfirmed ?? examDateConfirmed
        }
        settingsUpdatedAt = m.settingsUpdatedAt ?? settingsUpdatedAt
        resetAt = m.resetAt ?? resetAt
        lastSync = .now
        save()
        refreshPlan()
    }

    private func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Wire format shared with the web app (web/src/app.js) and the Worker (web/worker.js).
struct SyncState: Codable, Sendable {
    struct Progress: Codable, Sendable {
        var box: Int, seen: Int, correct: Int, wrong: Int
        var lastWrong: Bool
        var due: Double?
        var bookmarked: Bool
        var updatedAt: Double
    }
    struct Exam: Codable, Sendable {
        var id: String, date: String
        var correct: Int, total: Int
        var duration: Double
        var wrongIds: [String]
    }
    struct Plan: Codable, Sendable {
        var day: String
        var newIds: [String], reviewIds: [String], done: [String]
    }
    var v: Int
    var progress: [String: Progress]
    var exams: [Exam]
    var plan: Plan?
    var examDate: String?
    var examDateConfirmed: Bool?
    var settingsUpdatedAt: Double?
    var resetAt: Double?

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
