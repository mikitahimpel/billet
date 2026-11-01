/// A full-precision stroke, used while drawing live.
public struct Stroke: Codable, Hashable, Sendable {
  public let color: String
  public let width: Double
  public let points: [Point]

  public init(color: String, width: Double, points: [Point]) {
    self.color = color
    self.width = width
    self.points = points
  }
}
