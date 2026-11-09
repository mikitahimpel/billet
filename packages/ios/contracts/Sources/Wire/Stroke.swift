/// Decoding enforces the contract's colour pattern; building one in code does not, so drawing
/// code stays free of throws.
public struct Stroke: Codable, Hashable, Sendable {
  public let color: String
  public let width: Double
  public let points: [Point]

  public init(color: String, width: Double, points: [Point]) {
    self.color = color
    self.width = width
    self.points = points
  }

  private enum CodingKeys: String, CodingKey {
    case color
    case width
    case points
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    color = try container.decode(String.self, forKey: .color)
    guard StrokeColor.isValid(color) else {
      throw DecodingError.dataCorruptedError(
        forKey: .color, in: container, debugDescription: "expected #RRGGBB, got \(color)")
    }
    width = try container.decode(Double.self, forKey: .width)
    points = try container.decode([Point].self, forKey: .points)
  }
}
