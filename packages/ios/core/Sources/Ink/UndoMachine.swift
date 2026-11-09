import BilletKit
import Wire

public enum UndoMachine: Machine {
  public struct State: Hashable, Sendable {
    public var strokes: [Stroke]
    public var redoable: [Stroke]

    public init(strokes: [Stroke] = [], redoable: [Stroke] = []) {
      self.strokes = strokes
      self.redoable = redoable
    }
  }

  public enum Event: Hashable, Sendable {
    case strokeCommitted(Stroke)
    case undo
    case redo
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Never]) {
    var next = state
    switch event {
    case .strokeCommitted(let stroke):
      next.strokes.append(stroke)
      next.redoable = []
    case .undo:
      if let stroke = next.strokes.popLast() { next.redoable.append(stroke) }
    case .redo:
      if let stroke = next.redoable.popLast() { next.strokes.append(stroke) }
    }
    return (next, [])
  }
}
