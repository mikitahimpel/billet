import Foundation
import Observation

/// The couple's love streak, after TikTok's DM streaks (docs/love-streak.md): every day the couple does something
/// together in the app — pets or treats Mochi, adds a moment, pins a note, swipes a date idea or checks in a mood —
/// the flame grows by one. Miss a whole day and it goes out; one missed day can be restored once a month.
nonisolated struct LoveStreak: Codable, Hashable {
    /// Days in a row up to `lastDay`; kept after the streak breaks so a restore can bring it back.
    var count = 0
    /// Start of the last day that counted.
    var lastDay: Date?
    var best = 0
    /// Start of the day the last restore was used.
    var lastRestore: Date?

    static let milestones = [3, 7, 14, 30, 50, 100, 200, 365]
    /// Days between restores.
    static let restoreCooldown = 30
    /// Shorter streaks aren't worth a restore.
    static let restoreMinimum = 3

    enum Status: Equatable {
        /// No streak yet, or it went out.
        case cold
        /// Today already counts.
        case done
        /// Alive, but today doesn't count yet; it goes out at midnight.
        case atRisk
        /// Went out after one missed day and can still be restored.
        case restorable
    }

    func status(on date: Date = .now, calendar: Calendar = .current) -> Status {
        guard let lastDay, count > 0 else { return .cold }
        switch daysSince(lastDay, to: date, calendar: calendar) {
        case 0: return .done
        case 1: return .atRisk
        case 2 where canRestore(on: date, calendar: calendar): return .restorable
        default: return .cold
        }
    }

    /// The flame's number today: zero once the streak is out.
    func current(on date: Date = .now, calendar: Calendar = .current) -> Int {
        switch status(on: date, calendar: calendar) {
        case .done, .atRisk: count
        case .cold, .restorable: 0
        }
    }

    /// The highest milestone reached, and the next one to reach.
    func milestone(on date: Date = .now) -> (reached: Int?, next: Int?) {
        let days = current(on: date)
        return (Self.milestones.last { $0 <= days }, Self.milestones.first { $0 > days })
    }

    /// A qualifying action happened; the first one each day grows the streak.
    mutating func record(on date: Date = .now, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if let lastDay, lastDay == day { return }
        count = lastDay.map { daysSince($0, to: date, calendar: calendar) == 1 } == true ? count + 1 : 1
        lastDay = day
        best = max(best, count)
    }

    /// Fills in the missed day, so today's first action continues the old streak.
    mutating func restore(on date: Date = .now, calendar: Calendar = .current) {
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

/// The streak in the app group, next to the other shared stores.
@Observable
final class StreakStore {
    private(set) var streak: LoveStreak

    private let file: String

    init(file: String = "Us/streak.json") {
        self.file = file
        streak = SharedFile.read(LoveStreak.self, from: file) ?? LoveStreak()
    }

    func reload() {
        if let saved = SharedFile.read(LoveStreak.self, from: file) { streak = saved }
    }

    func record() { update { $0.record() } }

    func restore() { update { $0.restore() } }

    private func update(_ change: (inout LoveStreak) -> Void) {
        let old = streak
        change(&streak)
        if streak != old { SharedFile.write(streak, to: file) }
    }
}
