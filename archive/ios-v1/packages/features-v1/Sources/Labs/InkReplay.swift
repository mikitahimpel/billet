import Foundation
import Wire

/// A note drawn again in the order it was drawn. Notes carry no timestamps, so the pace is made
/// up: it follows how much ink there is, and never runs for less than a moment or past a few
/// seconds.
public enum InkReplay {
  public static let shortest = 1.5
  public static let longest = 6.0

  /// Seconds the whole note takes to draw.
  public static func duration(of strokes: [Stroke]) -> Double {
    min(longest, max(shortest, 0.8 + totalLength(of: strokes) * 3))
  }

  /// The strokes as they stood when `progress` (0...1) of the ink was down: whole strokes first,
  /// then the one being drawn, cut where the pen would be.
  public static func strokes(of strokes: [Stroke], progress: Double) -> [Stroke] {
    let progress = min(1, max(0, progress))
    if progress >= 1 { return strokes }
    if progress <= 0 { return [] }
    let total = totalLength(of: strokes)
    guard total > 0 else { return progress > 0 ? strokes : [] }
    var remaining = progress * total
    var shown: [Stroke] = []
    for stroke in strokes {
      let length = length(of: stroke)
      if length <= remaining {
        shown.append(stroke)
        remaining -= length
        continue
      }
      shown.append(
        Stroke(color: stroke.color, width: stroke.width, points: cut(stroke.points, at: remaining)))
      break
    }
    return shown
  }

  private static func cut(_ points: [Point], at distance: Double) -> [Point] {
    guard var last = points.first else { return [] }
    var result = [last]
    var left = distance
    for point in points.dropFirst() {
      let step = hypot(point.x - last.x, point.y - last.y)
      if step >= left {
        let t = step > 0 ? left / step : 0
        result.append(Point(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t))
        return result
      }
      result.append(point)
      left -= step
      last = point
    }
    return result
  }

  private static func length(of stroke: Stroke) -> Double {
    zip(stroke.points, stroke.points.dropFirst()).reduce(0) {
      $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
    }
  }

  private static func totalLength(of strokes: [Stroke]) -> Double {
    strokes.reduce(0) { $0 + length(of: $1) }
  }
}
