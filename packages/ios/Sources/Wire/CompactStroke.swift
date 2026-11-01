/// A quantised stroke. `points` is flat: `[x0, y0, x1, y1, ...]`.
public struct CompactStroke: Codable, Hashable, Sendable {
  public let color: String
  public let width: Int
  public let points: [Int]

  public init(color: String, width: Int, points: [Int]) {
    self.color = color
    self.width = width
    self.points = points
  }
}
