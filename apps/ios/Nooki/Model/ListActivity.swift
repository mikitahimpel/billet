import Foundation
import MomentsInterface
import OurioShared
import UsInterface

/// A partner's newest change to a list: what they did, how many times that day, and when.
nonisolated struct ListChange: Equatable {
    enum Kind { case added, done }

    var kind: Kind
    var count: Int
    var at: Date
}

extension UsList {
    /// The partner's newest add or tick, counted with the others of the same kind they made that day. An edit keeps
    /// no date, so it doesn't count.
    nonisolated func latestChange(by partner: String, calendar: Calendar = .current) -> ListChange? {
        let added = items.filter { $0.author == partner }.map { (ListChange.Kind.added, $0.added) }
        let done = items.compactMap { item in item.doneBy == partner ? item.done.map { (ListChange.Kind.done, $0) } : nil }
        guard let newest = (added + done).max(by: { $0.1 < $1.1 }) else { return nil }
        let count = (newest.0 == .added ? added : done).count { calendar.isDate($0.1, inSameDayAs: newest.1) }
        return ListChange(kind: newest.0, count: count, at: newest.1)
    }
}

/// How the Us tab lays the lists out: a rich card for the first Groceries, To watch and Places to go, the one the
/// partner changed last first, and every other list as a row.
nonisolated struct UsListsLayout {
    static let richKinds: [ListKind] = [.groceries, .watch, .travel]

    var cards: [UsList]
    var rows: [UsList]

    init(lists: [UsList], partner: String) {
        let firsts = Self.richKinds.compactMap { kind in lists.first { $0.kind == kind } }
        let changed = Dictionary(uniqueKeysWithValues: firsts.map { ($0.id, $0.latestChange(by: partner)?.at) })
        cards = firsts.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (changed[lhs.element.id] ?? nil, changed[rhs.element.id] ?? nil)
                switch (left, right) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
        let shown = Set(firsts.map(\.id))
        rows = lists.filter { !shown.contains($0.id) }
    }
}
