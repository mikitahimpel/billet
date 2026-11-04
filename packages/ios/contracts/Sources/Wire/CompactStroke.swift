/// A quantised stroke. `points` is flat: `[x0, y0, x1, y1, ...]`.
///
/// Decoding enforces what the contract's schema does: a `#RRGGBB` colour and an even number of
/// values in `points`.
public struct CompactStroke: Codable, Hashable, Sendable {
  public let color: String
  public let width: Int
  public let points: [Int]

  public init(color: String, width: Int, points: [Int]) {
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
    width = try container.decode(Int.self, forKey: .width)
    points = try container.decode([Int].self, forKey: .points)
    guard points.count.isMultiple(of: 2) else {
      throw DecodingError.dataCorruptedError(
        forKey: .points, in: container, debugDescription: "expected an even number of values")
    }
  }
}
