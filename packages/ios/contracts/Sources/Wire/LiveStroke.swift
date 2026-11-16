/// A finished stroke under the id its sender gave it live, so a partner can replace or drop it.
/// On the wire it is flat: `id`, `color`, `width`, `points`.
public struct LiveStroke: Codable, Hashable, Sendable {
  /// The contract's `maxShownPoints`, per `strokesShown` frame: a longer stroke is thinned.
  public static let maxPoints = 800
  /// The contract's `maxShownStrokes`, per `strokesShown` frame.
  public static let maxPerFrame = 64
  /// The contract's `maxKeptStrokes`.
  public static let maxKept = 500

  public let id: Int
  public let stroke: Stroke

  public init(id: Int, stroke: Stroke) {
    self.id = id
    self.stroke = stroke
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case color
    case width
    case points
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let start = try LiveStrokeStart(from: decoder)
    let points = try container.decode([Point].self, forKey: .points)
    guard (1...Self.maxPoints).contains(points.count) else {
      throw DecodingError.dataCorruptedError(
        forKey: .points, in: container,
        debugDescription: "expected 1 to \(Self.maxPoints) points, got \(points.count)")
    }
    id = start.id
    stroke = Stroke(color: start.color, width: start.width, points: points)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(stroke.color, forKey: .color)
    try container.encode(stroke.width, forKey: .width)
    try container.encode(stroke.points, forKey: .points)
  }

  /// At most ``maxPoints`` points, evenly picked, the first and last kept.
  public var thinned: LiveStroke {
    let points = stroke.points
    guard points.count > Self.maxPoints else { return self }
    let step = Double(points.count - 1) / Double(Self.maxPoints - 1)
    let picked = (0..<Self.maxPoints).map { points[Int((Double($0) * step).rounded())] }
    return LiveStroke(
      id: id, stroke: Stroke(color: stroke.color, width: stroke.width, points: picked))
  }
}

extension LiveStroke {
  /// Refuses an empty frame, or one over ``maxPerFrame`` strokes or ``maxPoints`` points.
  static func decodeShown<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key
  ) throws -> [LiveStroke] {
    let strokes = try container.decode([LiveStroke].self, forKey: key)
    let points = strokes.reduce(0) { $0 + $1.stroke.points.count }
    guard (1...maxPerFrame).contains(strokes.count), points <= maxPoints else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: container,
        debugDescription: "expected 1 to \(maxPerFrame) strokes and \(maxPoints) points")
    }
    return strokes
  }

  /// Refuses more than ``maxKept`` ids.
  static func decodeKept<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key
  ) throws -> [Int] {
    let ids = try container.decode([Int].self, forKey: key)
    guard ids.count <= maxKept else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: container,
        debugDescription: "expected at most \(maxKept) ids, got \(ids.count)")
    }
    return ids
  }
}
