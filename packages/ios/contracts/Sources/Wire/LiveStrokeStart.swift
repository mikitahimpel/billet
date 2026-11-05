/// The start of a stroke drawn live on the shared canvas: its id and its ink.
///
/// `id` names the stroke among its sender's open strokes. Decoding enforces the contract's colour
/// pattern; building one in code does not.
public struct LiveStrokeStart: Codable, Hashable, Sendable {
  /// The most points one `strokePoints` frame may carry, as the contract's `maxLivePoints`.
  public static let maxPoints = 64

  public let id: Int
  public let color: String
  public let width: Double

  public init(id: Int, color: String, width: Double) {
    self.id = id
    self.color = color
    self.width = width
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case color
    case width
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    color = try container.decode(String.self, forKey: .color)
    guard StrokeColor.isValid(color) else {
      throw DecodingError.dataCorruptedError(
        forKey: .color, in: container, debugDescription: "expected #RRGGBB, got \(color)")
    }
    width = try container.decode(Double.self, forKey: .width)
  }

  /// Decodes a points batch, refusing an empty one or one over ``maxPoints``.
  static func decodePoints<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key
  ) throws -> [Point] {
    let points = try container.decode([Point].self, forKey: key)
    guard (1...maxPoints).contains(points.count) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: container,
        debugDescription: "expected 1 to \(maxPoints) points, got \(points.count)")
    }
    return points
  }
}
