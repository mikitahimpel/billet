import Foundation
import Observation

/// Grows by one each day the couple does something together (docs/love-streak.md); a whole missed day puts it out,
/// and one missed day can be restored once a month.
public nonisolated struct LoveStreak: Codable, Hashable, Sendable {
    /// Days in a row up to `lastDay`; kept after the streak breaks so a restore can bring it back.
    public var count = 0
    /// Start of the last day that counted.
    public var lastDay: Date?
    public var best = 0
    /// Start of the day the last restore was used.
    public var lastRestore: Date?

    public init(count: Int = 0, lastDay: Date? = nil, best: Int = 0, lastRestore: Date? = nil) {
        self.count = count
        self.lastDay = lastDay
        self.best = best
        self.lastRestore = lastRestore
    }

    public static let milestones = [3, 7, 14, 30, 50, 100, 200, 365]
    /// In days.
    public static let restoreCooldown = 30
    /// Shorter streaks aren't worth a restore.
    public static let restoreMinimum = 3

    public enum Status: Equatable, Sendable {
        /// No streak yet, or it went out.
        case cold
        /// Today already counts.
        case done
        /// Alive, but today doesn't count yet; it goes out at midnight.
        case atRisk
        /// Went out after one missed day and can still be restored.
        case restorable
    }

    public func status(on date: Date = .now, calendar: Calendar = .current) -> Status {
        guard let lastDay, count > 0 else { return .cold }
        switch daysSince(lastDay, to: date, calendar: calendar) {
        case 0: return .done
        case 1: return .atRisk
        case 2 where canRestore(on: date, calendar: calendar): return .restorable
        default: return .cold
        }
    }

    /// The flame's number today: zero once the streak is out.
    public func current(on date: Date = .now, calendar: Calendar = .current) -> Int {
        switch status(on: date, calendar: calendar) {
        case .done, .atRisk: count
        case .cold, .restorable: 0
        }
    }

    public func milestone(on date: Date = .now) -> (reached: Int?, next: Int?) {
        let days = current(on: date)
        return (Self.milestones.last { $0 <= days }, Self.milestones.first { $0 > days })
    }

    /// A qualifying action happened; the first one each day grows the streak.
    public mutating func record(on date: Date = .now, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if let lastDay, lastDay == day { return }
        count = lastDay.map { daysSince($0, to: date, calendar: calendar) == 1 } == true ? count + 1 : 1
        lastDay = day
        best = max(best, count)
    }

    /// Fills in the missed day, so today's first action continues the old streak.
    public mutating func restore(on date: Date = .now, calendar: Calendar = .current) {
        guard status(on: date, calendar: calendar) == .restorable else { return }
        let today = calendar.startOfDay(for: date)
        lastDay = calendar.date(byAdding: .day, value: -1, to: today)
        lastRestore = today
    }

    private func canRestore(on date: Date, calendar: Calendar) -> Bool {
        guard count >= Self.restoreMinimum else { return false }
        guard let lastRestore else { return true }
        return daysSince(lastRestore, to: date, calendar: calendar) >= Self.restoreCooldown
    }

    private func daysSince(_ day: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// The room counts one streak for the couple and keeps the restore cooldown for both; each call answers it.
public nonisolated struct StreakRemote: Sendable {
    public enum Answer: Sendable, Equatable {
        case streak(LoveStreak)
        /// The room would not: a restore it can't make, or a pair it no longer has.
        case refused
        /// The room could not be reached; nothing changed there.
        case offline
    }

    public var load: @Sendable () async -> Answer
    public var record: @Sendable (_ at: Date) async -> Answer
    public var restore: @Sendable () async -> Answer

    public init(load: @escaping @Sendable () async -> Answer, record: @escaping @Sendable (_ at: Date) async -> Answer, restore: @escaping @Sendable () async -> Answer) {
        self.load = load
        self.record = record
        self.restore = restore
    }
}

/// The streak in the app group, next to the other shared stores. Once paired it follows the pair's room: the file is
/// the room's streak as last read, with this phone's own days on top until the room has them, so it shows the same
/// flame on both phones and still counts a day done offline.
@MainActor
@Observable
public final class StreakStore {
    public private(set) var streak: LoveStreak
    /// When this phone grew the streak while the room had not heard of it yet.
    public private(set) var unsent: [Date]

    private let file: String
    private let unsentFile: String
    @ObservationIgnored private var remote: StreakRemote?
    @ObservationIgnored private var flushing = false

    public init(file: String = "Us/streak.json") {
        self.file = file
        unsentFile = file.replacingOccurrences(of: ".json", with: "-unsent.json")
        streak = SharedFile.read(LoveStreak.self, from: file) ?? LoveStreak()
        unsent = SharedFile.read([Date].self, from: unsentFile) ?? []
    }

    public func reload() {
        if let saved = SharedFile.read(LoveStreak.self, from: file) { streak = saved }
    }

    /// Follows the pair's streak through `remote`, or keeps it on this phone with nil.
    public func follow(_ remote: StreakRemote?) async {
        self.remote = remote
        if remote == nil, !unsent.isEmpty {
            unsent = []
            SharedFile.write(unsent, to: unsentFile)
        }
        await refresh()
    }

    /// Sends the days that waited, then reads the room's streak. Offline it stays as kept.
    public func refresh() async {
        guard let remote else { return }
        await flush()
        if case .streak(let shared) = await remote.load() { take(shared) }
    }

    /// The room's streak as the socket pushed it after either partner changed it. Ignored before pairing, when the
    /// streak is this phone's own.
    public func received(_ shared: LoveStreak) {
        guard remote != nil else { return }
        take(shared)
    }

    public func record(at date: Date = .now) {
        guard update({ $0.record(on: date) }), remote != nil else { return }
        unsent.append(date)
        SharedFile.write(unsent, to: unsentFile)
        Task { await flush() }
    }

    /// Brings the streak back after one missed day: in the pair's room once paired, so the partner sees it too and the
    /// monthly restore is the couple's. Whether it came back.
    @discardableResult
    public func restore(on date: Date = .now) async -> Bool {
        guard let remote else {
            return update { $0.restore(on: date) }
        }
        switch await remote.restore() {
        case .streak(let shared):
            take(shared)
            return true
        case .refused:
            await refresh()
            return false
        case .offline:
            return false
        }
    }

    /// Sends each waiting day in order; a drop keeps the rest, and a day the room refuses is let go.
    private func flush() async {
        guard let remote, !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let date = unsent.first {
            let answer = await remote.record(date)
            if answer == .offline { return }
            unsent.removeFirst()
            SharedFile.write(unsent, to: unsentFile)
            if case .streak(let shared) = answer { take(shared) }
        }
    }

    /// The room's streak, with the days still waiting counted on top.
    private func take(_ shared: LoveStreak) {
        var next = shared
        for date in unsent { next.record(on: date) }
        guard next != streak else { return }
        streak = next
        SharedFile.write(streak, to: file)
    }

    @discardableResult
    private func update(_ change: (inout LoveStreak) -> Void) -> Bool {
        let old = streak
        change(&streak)
        guard streak != old else { return false }
        SharedFile.write(streak, to: file)
        return true
    }
}
