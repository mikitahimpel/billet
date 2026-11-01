import Foundation
import Wire

/// Turns full-precision strokes into the compact rendition that travels inside a push.
///
/// Stroke coordinates and widths are fractions of the canvas width (the unit square), so a
/// drawing has the same shape at any size. Every tunable lives in ``Parameters`` because the
/// grid, simplification and budget are still being decided in #13.
public enum InkEncoder {
  public struct Parameters: Hashable, Sendable {
    /// Integer steps across the unit square.
    public var resolution: Int
    /// Largest distance, in unit-square fractions, a simplified stroke may stray from the original.
    public var tolerance: Double
    /// Bytes the encoded JSON must stay under.
    public var budget: Int

    public init(resolution: Int = 1024, tolerance: Double = 0.002, budget: Int = 3072) {
      self.resolution = resolution
      self.tolerance = tolerance
      self.budget = budget
    }
  }

  /// Simplifies and quantises `strokes` with exactly the given parameters.
  public static func encode(
    _ strokes: [Stroke], parameters: Parameters = Parameters()
  ) throws(InkError) -> CompactStrokes {
    guard parameters.resolution > 0, parameters.tolerance >= 0 else {
      throw InkError.invalidParameters
    }
    let scale = Double(parameters.resolution)
    return CompactStrokes(
      strokes: strokes.map { stroke in
        var points: [Int] = []
        var lastX: Int?
        var lastY: Int?
        for point in simplify(stroke.points, tolerance: parameters.tolerance) {
          let x = Int((point.x * scale).rounded())
          let y = Int((point.y * scale).rounded())
          if x == lastX && y == lastY { continue }
          points.append(contentsOf: [x, y])
          lastX = x
          lastY = y
        }
        return CompactStroke(
          color: stroke.color, width: max(1, Int((stroke.width * scale).rounded())),
          points: points)
      })
  }

  /// Encodes with the given tolerance, then doubles it until the result fits `budget`.
  public static func encodeWithinBudget(
    _ strokes: [Stroke], parameters: Parameters = Parameters()
  ) throws(InkError) -> CompactStrokes {
    var attempt = parameters
    attempt.tolerance = max(parameters.tolerance, 0.0005)
    var smallest = Int.max
    while attempt.tolerance <= 0.5 {
      let encoded = try encode(strokes, parameters: attempt)
      let size = byteCount(encoded)
      if size <= parameters.budget { return encoded }
      smallest = min(smallest, size)
      attempt.tolerance *= 2
    }
    throw InkError.overBudget(budget: parameters.budget, smallest: smallest)
  }

  /// The size in bytes of the JSON that goes on the wire.
  public static func byteCount(_ compact: CompactStrokes) -> Int {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(compact).count) ?? Int.max
  }

  /// Ramer–Douglas–Peucker. Keeps the endpoints of every stroke.
  static func simplify(_ points: [Point], tolerance: Double) -> [Point] {
    guard points.count > 2 else { return points }
    var keep = [Bool](repeating: false, count: points.count)
    keep[0] = true
    keep[points.count - 1] = true
    var pending = [(0, points.count - 1)]
    while let (first, last) = pending.popLast() {
      guard last - first > 1 else { continue }
      var farthest = first
      var distance = 0.0
      for index in (first + 1)..<last {
        let candidate = perpendicularDistance(points[index], from: points[first], to: points[last])
        if candidate > distance {
          distance = candidate
          farthest = index
        }
      }
      if distance > tolerance {
        keep[farthest] = true
        pending.append((first, farthest))
        pending.append((farthest, last))
      }
    }
    return zip(points, keep).filter(\.1).map(\.0)
  }

  private static func perpendicularDistance(_ p: Point, from a: Point, to b: Point) -> Double {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > 0 else {
      return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
    }
    return abs(dy * (p.x - a.x) - dx * (p.y - a.y)) / length
  }
}
