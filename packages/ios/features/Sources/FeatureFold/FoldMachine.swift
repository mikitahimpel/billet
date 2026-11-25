import BilletKit
import FoldInterface
import Wire

/// Fold and draw on one phone, passed from hand to hand: the first draws the top half of a creature down to
/// the fold, the second sees only the strip above the fold and draws the rest, and then the sheet opens.
public enum FoldMachine: Machine {
  public enum Problem: Equatable, Sendable {
    case nothingDrawn
    /// The top half has to come down into the strip that shows, or the second has nothing to go on from.
    case stopsShortOfTheFold
  }

  public struct Sketch: Equatable, Sendable {
    public let half: FoldHalf
    /// The top half, hidden but for its strip, while the bottom is drawn.
    public let above: [Stroke]
    public var strokes: [Stroke] = []
    /// The line under the finger; nil when it is lifted.
    public var current: [Point]?
    public var refused: Problem?
    /// Creatures finished since the screen opened.
    public let round: Int

    public init(half: FoldHalf, above: [Stroke] = [], round: Int) {
      self.half = half
      self.above = above
      self.round = round
    }

    /// Everything of this half to draw, the line in progress last.
    public var visible: [Stroke] {
      guard let current else { return strokes }
      return strokes + [Stroke(color: half.ink, width: FoldRules.penWidth, points: current)]
    }

    /// What shows of the other half: its strip above the fold.
    public var peek: [Stroke] { FoldSheet.peek(of: above) }

    public var problem: Problem? {
      if strokes.isEmpty { return .nothingDrawn }
      switch half {
      case .top: return FoldSheet.reachesFold(strokes) ? nil : .stopsShortOfTheFold
      case .bottom: return nil
      }
    }
  }

  public struct Folded: Equatable, Sendable {
    public let top: [Stroke]
    public let round: Int
  }

  public struct Opened: Equatable, Sendable {
    public let creature: FoldCreature
    public let round: Int
  }

  public enum State: Equatable, Sendable {
    case drawing(Sketch)
    /// The sheet is folded and the phone is on its way to the second drawer.
    case folded(Folded)
    case opened(Opened)
  }

  public enum Event: Equatable, Sendable {
    /// The finger is on the sheet, at a place on the whole sheet.
    case touched(Point)
    case lifted
    case undo
    case cleared
    /// Done with this half: the top is folded away, the bottom opens the sheet.
    case done
    case took
    /// A new sheet, the other one drawing first.
    case again
  }

  public enum Output: Equatable, Sendable {}

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.drawing(var sketch), .touched(let point)):
      sketch.current = (sketch.current ?? []) + [sketch.half.kept(point)]
      sketch.refused = nil
      return (.drawing(sketch), [])

    case (.drawing(var sketch), .lifted):
      guard let points = sketch.current else { return (state, []) }
      sketch.current = nil
      sketch.strokes.append(
        Stroke(color: sketch.half.ink, width: FoldRules.penWidth, points: points))
      return (.drawing(sketch), [])

    case (.drawing(var sketch), .undo):
      guard sketch.current == nil, !sketch.strokes.isEmpty else { return (state, []) }
      sketch.strokes.removeLast()
      sketch.refused = nil
      return (.drawing(sketch), [])

    case (.drawing(var sketch), .cleared):
      guard sketch.current == nil, !sketch.strokes.isEmpty else { return (state, []) }
      sketch.strokes = []
      sketch.refused = nil
      return (.drawing(sketch), [])

    case (.drawing(var sketch), .done):
      guard sketch.current == nil else { return (state, []) }
      sketch.refused = sketch.problem
      guard sketch.refused == nil else { return (.drawing(sketch), []) }
      switch sketch.half {
      case .top:
        return (.folded(Folded(top: sketch.strokes, round: sketch.round)), [])
      case .bottom:
        let creature = FoldCreature(top: sketch.above, bottom: sketch.strokes)
        return (.opened(Opened(creature: creature, round: sketch.round)), [])
      }

    case (.folded(let folded), .took):
      return (.drawing(Sketch(half: .bottom, above: folded.top, round: folded.round)), [])

    case (.opened(let opened), .again):
      return (.drawing(Sketch(half: .top, round: opened.round + 1)), [])

    case (.drawing, .took), (.drawing, .again),
      (.folded, .touched), (.folded, .lifted), (.folded, .undo), (.folded, .cleared),
      (.folded, .done), (.folded, .again),
      (.opened, .touched), (.opened, .lifted), (.opened, .undo), (.opened, .cleared),
      (.opened, .done), (.opened, .took):
      return (state, [])
    }
  }

  /// The interpreter handed to a ``Store``. Generic because ``Output`` has no cases, and the compiler flags
  /// the body of a function that takes an uninhabited type as unreachable.
  public static func run<Ignored: Sendable>(_ output: Ignored) async -> Event? { nil }
}

public typealias FoldStore = Store<FoldMachine>

extension Store where M == FoldMachine {
  @MainActor
  public static func fold() -> FoldStore {
    Store(initial: .drawing(FoldMachine.Sketch(half: .top, round: 0)), run: FoldMachine.run)
  }
}
