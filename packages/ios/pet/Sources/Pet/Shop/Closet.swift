/// What the pair owns and has not put in the room, with a count for each item.
public struct Closet: Codable, Hashable, Sendable {
  public private(set) var counts: [ShopItem.ID: Int]

  public init(counts: [ShopItem.ID: Int] = [:]) {
    self.counts = counts.filter { $0.value > 0 }
  }

  public func count(of id: ShopItem.ID) -> Int {
    counts[id] ?? 0
  }

  public var isEmpty: Bool { counts.isEmpty }

  mutating func add(_ id: ShopItem.ID) {
    counts[id, default: 0] += 1
  }

  /// Takes one out, or throws when there is none.
  mutating func take(_ id: ShopItem.ID) throws(ShopError) {
    guard let have = counts[id], have > 0 else { throw .notInCloset }
    counts[id] = have > 1 ? have - 1 : nil
  }
}
