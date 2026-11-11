import Foundation

/// What the pair has put on grocery lists, by `GroceryWords.key`: how often, and the aisle last picked. Built from the
/// items this phone sees, both partners' included, so it outlives "Clear".
// note: misses items the partner added and cleared unseen here; a table in the pair's room would catch them.
public struct GroceryHistory: Codable, Hashable, Sendable {
  public struct Entry: Codable, Hashable, Sendable {
    /// The name as last written.
    public var text: String
    public var count = 0
    public var aisle: String?
    public var last: Date

    public init(text: String, count: Int = 0, aisle: String? = nil, last: Date) {
      self.text = text
      self.count = count
      self.aisle = aisle
      self.last = last
    }
  }

  public private(set) var entries: [String: Entry] = [:]
  /// Grocery items already counted. Only the ones still on a list are kept, since a deleted item never comes back.
  private var counted: Set<UUID> = []

  public init() {}

  /// Counts every grocery item seen for the first time and keeps the aisle a partner set on one.
  public mutating func observe(_ lists: [UsList]) {
    let items = lists.filter { $0.kind == .groceries }.flatMap(\.items).sorted {
      $0.added < $1.added
    }
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

  public func entry(for text: String) -> Entry? { entries[GroceryWords.key(text)] }

  /// The most bought first, the latest first among equals.
  public func often(limit: Int) -> [Entry] {
    Array(entries.values.sorted { ($0.count, $0.last) > ($1.count, $1.last) }.prefix(limit))
  }
}
