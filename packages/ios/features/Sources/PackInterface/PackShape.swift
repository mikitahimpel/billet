/// A square of the suitcase, or of a thing's outline. `y` grows downwards.
public struct PackCell: Hashable, Sendable, Comparable {
  public let x: Int
  public let y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  /// Reading order: row by row.
  public static func < (a: PackCell, b: PackCell) -> Bool { (a.y, a.x) < (b.y, b.x) }
}

/// The outline of a thing as squares. Always pushed against the top and the left, and in reading order, so two
/// outlines that cover the same squares are equal.
public struct PackShape: Hashable, Sendable {
  public let cells: [PackCell]

  public init(_ cells: some Sequence<PackCell>) {
    let all = Set(cells)
    let left = all.map(\.x).min() ?? 0
    let top = all.map(\.y).min() ?? 0
    self.cells = all.map { PackCell(x: $0.x - left, y: $0.y - top) }.sorted()
  }

  public var width: Int { (cells.map(\.x).max() ?? -1) + 1 }
  public var height: Int { (cells.map(\.y).max() ?? -1) + 1 }

  /// The square a finger puts down: the first in reading order, so it is always on the top row.
  public var anchor: PackCell { cells.first ?? PackCell(x: 0, y: 0) }

  /// The outline after so many quarter turns clockwise.
  public func turned(_ quarters: Int) -> PackShape {
    var shape = self
    for _ in 0..<(((quarters % 4) + 4) % 4) {
      shape = PackShape(shape.cells.map { PackCell(x: -$0.y, y: $0.x) })
    }
    return shape
  }

  /// The outlines a turn can give, each once: a square has one, a bar two.
  public var turns: [PackShape] {
    var seen: [PackShape] = []
    for quarters in 0..<4 {
      let shape = turned(quarters)
      if !seen.contains(shape) { seen.append(shape) }
    }
    return seen
  }
}
