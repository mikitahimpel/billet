import Foundation

/// What the pair has put on its grocery lists, by `GroceryWords.key`: how often, and the aisle a partner last picked
/// for it. Built from the items this phone sees, both partners' included, so it outlives "Clear".
// note: an item the partner added and cleared while this phone never loaded the lists is not counted; a table in the
// pair's room would catch it.
nonisolated struct GroceryHistory: Codable, Hashable {
    struct Entry: Codable, Hashable {
        /// The name as last written.
        var text: String
        var count = 0
        var aisle: String?
        var last: Date
    }

    private(set) var entries: [String: Entry] = [:]
    /// Grocery items already counted. Only the ones still on a list are kept, since a deleted item never comes back.
    private var counted: Set<UUID> = []

    /// Counts every grocery item seen for the first time and keeps the aisle a partner set on one.
    mutating func observe(_ lists: [UsList]) {
        let items = lists.filter { $0.kind == .groceries }.flatMap(\.items).sorted { $0.added < $1.added }
        for item in items {
            let key = GroceryWords.key(item.text)
            guard !key.isEmpty else { continue }
            var entry = entries[key] ?? Entry(text: item.text, last: item.added)
            if !counted.contains(item.id) {
                entry.count += 1
                entry.text = item.text
                entry.last = max(entry.last, item.added)
            }
            if let aisle = item.aisle { entry.aisle = aisle }
            entries[key] = entry
        }
        counted = Set(items.map(\.id))
    }

    func entry(for text: String) -> Entry? { entries[GroceryWords.key(text)] }

    /// The most bought first, the latest first among equals.
    func often(limit: Int) -> [Entry] {
        Array(entries.values.sorted { ($0.count, $0.last) > ($1.count, $1.last) }.prefix(limit))
    }
}
