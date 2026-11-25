import Wire

/// Every number of the folded sheet in one place. Lengths are fractions of the sheet's width, as strokes
/// carry them, so the same drawing fills any phone.
public enum FoldRules {
  /// The height of each half.
  public static let half = 0.62
  /// How much of the top half shows above the fold to whoever draws the bottom.
  public static let peek = 0.07
  public static let penWidth = 0.014
  /// The first drawer's ink and the second's, so the finished creature shows who drew which half.
  public static let topInk = "#D9784A"
  public static let bottomInk = "#9A7BB8"
}

public enum FoldHalf: Equatable, Sendable {
  case top, bottom

  /// Where on the whole sheet this half lies, from its upper edge to its lower.
  public var range: ClosedRange<Double> {
    switch self {
    case .top: 0...FoldRules.half
    case .bottom: FoldRules.half...(2 * FoldRules.half)
    }
  }

  public var ink: String {
    switch self {
    case .top: FoldRules.topInk
    case .bottom: FoldRules.bottomInk
    }
  }

  /// The point kept on the sheet and inside this half: nobody draws across the fold.
  public func kept(_ point: Point) -> Point {
    Point(
      x: min(max(point.x, 0), 1),
      y: min(max(point.y, range.lowerBound), range.upperBound))
  }
}

/// The sheet's geometry: what crosses the fold and what shows above it.
public enum FoldSheet {
  /// Where the strip that stays in view begins.
  public static var peekLine: Double { FoldRules.half - FoldRules.peek }

  /// Whether the top half comes down into the strip that will show, so there is something to go on from.
  public static func reachesFold(_ strokes: [Stroke]) -> Bool {
    strokes.contains { $0.points.contains { $0.y >= peekLine } }
  }

  /// The parts of the top half's lines that lie in the strip, cut where they cross into it.
  public static func peek(of strokes: [Stroke]) -> [Stroke] {
    strokes.flatMap { stroke in
      cut(stroke.points, below: peekLine).map {
        Stroke(color: stroke.color, width: stroke.width, points: $0)
      }
    }
  }

  /// The strokes moved up or down the sheet.
  public static func moved(_ strokes: [Stroke], by dy: Double) -> [Stroke] {
    strokes.map { stroke in
      Stroke(
        color: stroke.color, width: stroke.width,
        points: stroke.points.map { Point(x: $0.x, y: $0.y + dy) })
    }
  }

  /// The runs of a line at or below `line`, each begun and ended on it where the line crosses.
  static func cut(_ points: [Point], below line: Double) -> [[Point]] {
    var runs: [[Point]] = []
    var run: [Point] = []
    func crossing(_ a: Point, _ b: Point) -> Point {
      let t = (line - a.y) / (b.y - a.y)
      return Point(x: a.x + (b.x - a.x) * t, y: line)
    }
    for (index, point) in points.enumerated() {
      let inside = point.y >= line
      if index > 0 {
        let before = points[index - 1]
        if (before.y >= line) != inside { run.append(crossing(before, point)) }
      }
      if inside {
        run.append(point)
      } else if !run.isEmpty {
        runs.append(run)
        run = []
      }
    }
    if !run.isEmpty { runs.append(run) }
    return runs
  }
}
