import FoldInterface
import Testing
import Wire

@testable import FeatureFold

typealias M = FoldMachine

private func step(_ state: M.State, _ events: M.Event...) -> M.State {
  events.reduce(state) { M.transition($0, $1).0 }
}

private func sketch(_ state: M.State) -> M.Sketch? {
  if case .drawing(let sketch) = state { sketch } else { nil }
}

private let start = M.State.drawing(M.Sketch(half: .top, round: 0))
private let deep = Point(x: 0.5, y: FoldRules.half)

/// A top half with one line down to the fold.
private let headDrawn = step(start, .touched(Point(x: 0.5, y: 0.2)), .touched(deep), .lifted)

@Suite struct FoldMachineTests {
  @Test func aLineGrowsUnderTheFingerAndIsKeptWhenItLifts() {
    let drawing = step(start, .touched(Point(x: 0.1, y: 0.1)), .touched(Point(x: 0.2, y: 0.2)))
    #expect(sketch(drawing)?.current?.count == 2)
    #expect(sketch(drawing)?.strokes.isEmpty == true)
    #expect(sketch(drawing)?.visible.count == 1)
    let lifted = sketch(step(drawing, .lifted))
    #expect(lifted?.current == nil)
    #expect(lifted?.strokes.count == 1)
    #expect(lifted?.strokes.first?.color == FoldRules.topInk)
  }

  @Test func nobodyDrawsAcrossTheFold() {
    let over = sketch(step(start, .touched(Point(x: 0.5, y: 1.1))))
    #expect(over?.current == [Point(x: 0.5, y: FoldRules.half)])
    let bottom = M.State.drawing(M.Sketch(half: .bottom, round: 0))
    #expect(sketch(step(bottom, .touched(Point(x: 0.5, y: 0.1))))?.current == [deep])
  }

  @Test func undoTakesTheLastLineAndClearTakesAll() {
    let two = step(headDrawn, .touched(Point(x: 0.1, y: 0.1)), .lifted)
    #expect(sketch(step(two, .undo))?.strokes.count == 1)
    #expect(sketch(step(two, .cleared))?.strokes.isEmpty == true)
  }

  @Test func anEmptyTopIsNotFoldedAndSaysWhy() {
    let refused = step(start, .done)
    #expect(sketch(refused)?.refused == .nothingDrawn)
  }

  @Test func aTopThatStopsShortOfTheFoldIsNotFoldedAndSaysWhy() {
    let short = step(start, .touched(Point(x: 0.5, y: 0.1)), .lifted, .done)
    #expect(sketch(short)?.refused == .stopsShortOfTheFold)
    #expect(sketch(step(short, .touched(deep)))?.refused == nil)
  }

  @Test func aFoldedTopGoesToTheSecondWhoSeesOnlyItsStrip() {
    guard case .folded(let folded) = step(headDrawn, .done) else {
      Issue.record("not folded")
      return
    }
    #expect(folded.top.count == 1)
    let second = sketch(step(.folded(folded), .took))
    #expect(second?.half == .bottom)
    #expect(second?.strokes.isEmpty == true)
    #expect(second?.peek.count == 1)
    #expect(second?.peek.first?.points.allSatisfy { $0.y >= FoldSheet.peekLine } == true)
  }

  @Test func theBottomDoneOpensTheSheetWithBothHalves() {
    let second = step(headDrawn, .done, .took)
    #expect(sketch(step(second, .done))?.refused == .nothingDrawn)
    let finished = step(second, .touched(Point(x: 0.5, y: 0.9)), .lifted, .done)
    guard case .opened(let opened) = finished else {
      Issue.record("not opened")
      return
    }
    #expect(opened.creature.top.count == 1)
    #expect(opened.creature.bottom.count == 1)
    #expect(opened.creature.bottom.first?.color == FoldRules.bottomInk)
    #expect(opened.round == 0)
    let next = sketch(step(finished, .again))
    #expect(next?.half == .top)
    #expect(next?.round == 1)
    #expect(next?.strokes.isEmpty == true)
  }

  static let midLine = step(start, .touched(Point(x: 0.1, y: 0.1)))
  static let folded = M.State.folded(M.Folded(top: [], round: 0))
  static let opened = M.State.opened(
    M.Opened(creature: FoldCreature(top: [], bottom: []), round: 0))

  static let rejected: [(M.State, M.Event)] =
    [
      (start, .took), (start, .again), (start, .lifted), (start, .undo), (start, .cleared),
      (midLine, .undo), (midLine, .cleared), (midLine, .done),
    ]
    + [.touched(Point(x: 0, y: 0)), .lifted, .undo, .cleared, .done, .again].map { (folded, $0) }
    + [.touched(Point(x: 0, y: 0)), .lifted, .undo, .cleared, .done, .took].map { (opened, $0) }

  @Test(arguments: rejected)
  func eventsOutOfPlaceChangeNothing(state: M.State, event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
