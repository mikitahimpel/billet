import BilletKit
import Ink
import Wire

/// Drawing on the canvas: tool and colour, the stroke in progress, and undo, redo and clear.
///
/// `drawing` is the seam for sending later: it is the committed strokes, ready to encode.
public enum CanvasMachine: Machine {
  public struct State: Hashable, Sendable {
    public var tool: CanvasTool
    public var color: CanvasColor
    public var history: UndoMachine.State
    /// Points of the stroke being drawn, or `nil` when no finger is down.
    public var inProgress: [Point]?

    public init(
      tool: CanvasTool = .pen,
      color: CanvasColor = .ink,
      history: UndoMachine.State = .init(),
      inProgress: [Point]? = nil
    ) {
      self.tool = tool
      self.color = color
      self.history = history
      self.inProgress = inProgress
    }

    public var drawing: [Stroke] { history.strokes }

    /// The committed strokes plus the one being drawn, for rendering.
    public var visibleStrokes: [Stroke] {
      guard let points = inProgress else { return history.strokes }
      return history.strokes + [Stroke(color: color.hex, width: tool.width, points: points)]
    }

    public var canUndo: Bool { inProgress == nil && !history.strokes.isEmpty }
    public var canRedo: Bool { inProgress == nil && !history.redoable.isEmpty }
    public var canClear: Bool { inProgress == nil && !history.strokes.isEmpty }
  }

  /// Nothing to run yet. Sending will add its output here.
  public enum Output: Sendable {}

  public enum Event: Hashable, Sendable {
    case strokeBegan(Point)
    case strokeMoved(Point)
    case strokeEnded
    case toolSelected(CanvasTool)
    case colorSelected(CanvasColor)
    case undo
    case redo
    case cleared
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch (state.inProgress, event) {
    case (nil, .strokeBegan(let point)):
      next.inProgress = [point]

    case (.some(var points), .strokeMoved(let point)):
      points.append(point)
      next.inProgress = points

    case (.some(let points), .strokeEnded):
      next.inProgress = nil
      next.history =
        UndoMachine.transition(
          state.history,
          .strokeCommitted(Stroke(color: state.color.hex, width: state.tool.width, points: points))
        ).0

    case (nil, .toolSelected(let tool)):
      next.tool = tool

    case (nil, .colorSelected(let color)):
      next.color = color

    case (nil, .undo):
      next.history = UndoMachine.transition(state.history, .undo).0

    case (nil, .redo):
      next.history = UndoMachine.transition(state.history, .redo).0

    case (nil, .cleared):
      next.history = .init()

    case (.some, .strokeBegan),
      (nil, .strokeMoved),
      (nil, .strokeEnded),
      (.some, .toolSelected),
      (.some, .colorSelected),
      (.some, .undo),
      (.some, .redo),
      (.some, .cleared):
      break
    }
    return (next, [])
  }

  /// The interpreter handed to a ``Store``. Generic because ``Output`` has no cases yet, and the
  /// compiler flags the body of a function that takes an uninhabited type as unreachable.
  public static func run<Ignored: Sendable>(_ output: Ignored) async -> Event? {
    nil
  }
}
