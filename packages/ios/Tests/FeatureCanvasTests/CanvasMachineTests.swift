import Testing
import Wire

@testable import FeatureCanvas

@Suite("CanvasMachine")
struct CanvasMachineTests {
  private func apply(_ events: [CanvasMachine.Event]) -> CanvasMachine.State {
    events.reduce(CanvasMachine.State()) { CanvasMachine.transition($0, $1).0 }
  }

  private let a = Point(x: 0.1, y: 0.1)
  private let b = Point(x: 0.2, y: 0.3)

  private var oneStroke: [CanvasMachine.Event] {
    [.strokeBegan(a), .strokeMoved(b), .strokeEnded]
  }

  @Test func strokeIsInvisibleToHistoryUntilEnded() {
    let state = apply([.strokeBegan(a), .strokeMoved(b)])
    #expect(state.inProgress == [a, b])
    #expect(state.drawing.isEmpty)
    #expect(state.visibleStrokes.count == 1)
  }

  @Test func endedStrokeIsCommittedWithToolAndColor() {
    let state = apply([.toolSelected(.marker), .colorSelected(.clay)] + oneStroke)
    #expect(state.inProgress == nil)
    #expect(
      state.drawing == [
        Stroke(color: CanvasColor.clay.hex, width: CanvasTool.marker.width, points: [a, b])
      ])
  }

  @Test func undoThenRedoRestoresStroke() {
    let drawn = apply(oneStroke)
    let undone = apply(oneStroke + [.undo])
    #expect(undone.drawing.isEmpty)
    #expect(undone.canRedo)
    #expect(apply(oneStroke + [.undo, .redo]).drawing == drawn.drawing)
  }

  @Test func newStrokeDropsRedo() {
    let state = apply(oneStroke + [.undo] + oneStroke)
    #expect(state.drawing.count == 1)
    #expect(!state.canRedo)
  }

  @Test func clearEmptiesDrawingAndRedo() {
    let state = apply(oneStroke + oneStroke + [.undo, .cleared])
    #expect(state.drawing.isEmpty)
    #expect(!state.canUndo)
    #expect(!state.canRedo)
  }

  @Test func undoOnEmptyDrawingIsNoOp() {
    #expect(apply([.undo, .redo]) == CanvasMachine.State())
  }

  @Test func toolAndColorChangesAreIgnoredMidStroke() {
    let state = apply([.strokeBegan(a), .toolSelected(.marker), .colorSelected(.forest)])
    #expect(state.tool == .pen)
    #expect(state.color == .ink)
  }

  @Test func historyActionsAreIgnoredMidStroke() {
    let state = apply(oneStroke + [.strokeBegan(a), .undo, .cleared])
    #expect(state.drawing.count == 1)
    #expect(state.inProgress == [a])
  }

  @Test func strayMovesAndEndsAreIgnored() {
    #expect(apply([.strokeMoved(a), .strokeEnded]) == CanvasMachine.State())
  }
}
