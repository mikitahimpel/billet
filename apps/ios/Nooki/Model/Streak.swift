import Foundation
import Observation
import Persistence
import Wire

/// Grows by one each day both partners do something in the app (docs/love-streak.md); a whole missed day puts it
/// out, and one missed day can be restored once a month. On a phone with no partner its own day is enough.
public nonisolated struct LoveStreak: Codable, Hashable, Sendable {
    /// Days in a row up to `lastDay`; kept after the streak breaks so a restore can bring it back.
    public var count = 0
    /// Start of the last day that counted.
    public var lastDay: Date?
    public var best = 0
    /// Start of the day the last restore was used.
    public var lastRestore: Date?
    /// Starts of the days after `lastDay` that this phone's person did their part on, and that the partner did.
    public var mine: [Date] = []
    public var partner: [Date] = []

    public init(
        count: Int = 0, lastDay: Date? = nil, best: Int = 0, lastRestore: Date? = nil, mine: [Date] = [],
        partner: [Date] = []
    ) {
        self.count = count
        self.lastDay = lastDay
        self.best = best
        self.lastRestore = lastRestore
        self.mine = mine
        self.partner = partner
    }

    private enum CodingKeys: String, CodingKey {
        case count, lastDay, best, lastRestore, mine, partner
    }

    /// A file written before the marks reads with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decode(Int.self, forKey: .count)
        lastDay = try container.decodeIfPresent(Date.self, forKey: .lastDay)
        best = try container.decode(Int.self, forKey: .best)
        lastRestore = try container.decodeIfPresent(Date.self, forKey: .lastRestore)
        mine = try container.decodeIfPresent([Date].self, forKey: .mine) ?? []
        partner = try container.decodeIfPresent([Date].self, forKey: .partner) ?? []
    }

    /// Whose part today still waits for, while today isn't lit.
    public enum Turn: Equatable, Sendable {
        /// The partner did theirs; this phone's person hasn't.
        case yours
        /// This phone's person did theirs; the partner hasn't.
        case partners
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

    /// Nil once today is lit, or while neither partner did their part.
    public func turn(on date: Date = .now, calendar: Calendar = .current) -> Turn? {
        guard status(on: date, calendar: calendar) != .done else { return nil }
        let today = calendar.startOfDay(for: date)
        if mine.contains(today) { return .partners }
        if partner.contains(today) { return .yours }
        return nil
    }

    /// A qualifying action happened; the first one each day grows the streak. For a phone with no partner, and for
    /// a day both partners did.
    public mutating func record(on date: Date = .now, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if let lastDay, lastDay == day { return }
        count = lastDay.map { daysSince($0, to: date, calendar: calendar) == 1 } == true ? count + 1 : 1
        lastDay = day
        best = max(best, count)
        mine.removeAll { $0 <= day }
        partner.removeAll { $0 <= day }
    }

    /// This phone's person did their part: the day lights once the partner has too, as the room decides it.
    public mutating func mark(on date: Date = .now, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if let lastDay, lastDay >= day { return }
        if mine.contains(day) { return }
        if partner.contains(day) {
            record(on: date, calendar: calendar)
        } else {
            mine.append(day)
        }
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

extension LoveStreak {
    /// The room's streak in this phone's days: each local day is the start of that day in `calendar`. `you` is this
    /// phone's member, which tells its marks from the partner's; without it neither shows.
    public init(_ wire: PairStreak, you: String?, calendar: Calendar = .current) {
        let marks = wire.marks ?? []
        func days(mine: Bool) -> [Date] {
            guard let you else { return [] }
            return marks.filter { ($0.user.rawValue == you) == mine }.compactMap { Self.day($0.day, calendar) }
        }
        self.init(count: wire.days, lastDay: wire.lastDay.flatMap { Self.day($0, calendar) }, best: wire.best,
                  lastRestore: wire.restoredOn.flatMap { Self.day($0, calendar) }, mine: days(mine: true),
                  partner: days(mine: false))
    }

    /// `YYYY-MM-DD` as the start of that day.
    static func day(_ text: String, _ calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
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

    public nonisolated static let file = "Us/streak.json"

    public init(file: String = StreakStore.file) {
        self.file = file
        unsentFile = Self.unsentFile(of: file)
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

    /// Paired, this phone's day waits for the partner's; alone, it lights the day.
    public func record(at date: Date = .now) {
        let paired = remote != nil
        guard update({ paired ? $0.mark(on: date) : $0.record(on: date) }), paired else { return }
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

    /// The room's streak a push brought, for the widgets while the app may not be running; the app reads it when it
    /// next comes to the front.
    /// A push that comes after a later day lit (APNs keeps no order) is older than the file, and is dropped. Flushed,
    /// as the widgets read the file next and the extension may end at once.
    public nonisolated static func save(pushed shared: LoveStreak, file: String = StreakStore.file) {
        if let saved = SharedFile.read(LoveStreak.self, from: file)?.lastDay,
           shared.lastDay.map({ $0 < saved }) ?? true {
            return
        }
        let unsent = SharedFile.read([Date].self, from: unsentFile(of: file)) ?? []
        SharedFile.write(merged(shared, unsent: unsent), to: file)
        SharedFile.flush()
    }

    nonisolated static func unsentFile(of file: String) -> String {
        file.replacingOccurrences(of: ".json", with: "-unsent.json")
    }

    /// The room's streak, with the days this phone has not sent yet marked on top.
    nonisolated static func merged(_ shared: LoveStreak, unsent: [Date]) -> LoveStreak {
        var next = shared
        for date in unsent { next.mark(on: date) }
        return next
    }

    private func take(_ shared: LoveStreak) {
        let next = Self.merged(shared, unsent: unsent)
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
