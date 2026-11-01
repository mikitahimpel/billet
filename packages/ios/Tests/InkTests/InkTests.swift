import CoreGraphics
import Foundation
import Testing
import Wire

@testable import Ink

/// Deterministic reference drawing: five hand-like strokes of 400 jittery samples each.
func referenceDrawing() -> [Stroke] {
  let colors = ["#202020", "#404040", "#606060", "#808080", "#A0A0A0"]
  return colors.enumerated().map { index, color in
    let phase = Double(index)
    let points = (0..<400).map { step -> Point in
      let t = Double(step) / 399
      let x = 0.1 + 0.8 * t
      let y = 0.5 + 0.3 * sin(t * 6 * .pi + phase) * (0.4 + 0.1 * phase)
      let jitter = 0.0004 * sin(Double(step) * 37)
      return Point(x: x, y: y + jitter)
    }
    return Stroke(color: color, width: 0.01, points: points)
  }
}

@Suite struct InkEncodingTests {
  @Test func referenceDrawingFitsTheBudget() throws {
    let compact = try InkEncoder.encodeWithinBudget(referenceDrawing())
    let size = InkEncoder.byteCount(compact)
    #expect(size < 3072)
    #expect(compact.strokes.count == 5)
  }

  @Test func sizeShrinksAsToleranceGrows() throws {
    let drawing = referenceDrawing()
    let fine = try InkEncoder.encode(drawing, parameters: .init(tolerance: 0.0005))
    let coarse = try InkEncoder.encode(drawing, parameters: .init(tolerance: 0.01))
    #expect(InkEncoder.byteCount(coarse) < InkEncoder.byteCount(fine))
  }

  @Test func overBudgetThrowsWhenNothingFits() {
    let parameters = InkEncoder.Parameters(budget: 10)
    #expect(throws: InkError.self) {
      try InkEncoder.encodeWithinBudget(referenceDrawing(), parameters: parameters)
    }
  }

  @Test func roundTripStaysWithinQuantisation() throws {
    let drawing = referenceDrawing()
    let parameters = InkEncoder.Parameters(tolerance: 0)
    let decoded = try InkDecoder.decode(
      InkEncoder.encode(drawing, parameters: parameters), resolution: parameters.resolution)
    #expect(decoded.count == drawing.count)
    let step = 1 / Double(parameters.resolution)
    for (original, restored) in zip(drawing, decoded) {
      #expect(original.color == restored.color)
      #expect(abs(original.width - restored.width) <= step)
      for point in restored.points {
        let nearest =
          original.points.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .infinity
        #expect(nearest <= step)
      }
    }
  }

  @Test func compactRoundTripsThroughWireJSON() throws {
    let compact = try InkEncoder.encode(referenceDrawing())
    let data = try JSONEncoder().encode(compact)
    #expect(try JSONDecoder().decode(CompactStrokes.self, from: data) == compact)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"version\":1"))
  }

  @Test func encodedPointsAreEvenAndEndpointsSurvive() throws {
    let compact = try InkEncoder.encode(referenceDrawing(), parameters: .init(tolerance: 0.05))
    for stroke in compact.strokes {
      #expect(stroke.points.count.isMultiple(of: 2))
      #expect(stroke.points.count >= 4)
    }
  }

  @Test func oddPointCountIsRejected() {
    let bad = CompactStrokes(strokes: [
      CompactStroke(color: "#000000", width: 1, points: [1, 2, 3])
    ])
    #expect(throws: InkError.oddPointCount(strokeIndex: 0)) { try InkDecoder.decode(bad) }
  }

  @Test func invalidParametersAreRejected() {
    #expect(throws: InkError.invalidParameters) {
      try InkEncoder.encode([], parameters: .init(resolution: 0))
    }
  }
}

@Suite struct UndoMachineTests {
  func stroke(_ x: Double) -> Stroke {
    Stroke(color: "#000000", width: 0.01, points: [Point(x: x, y: x)])
  }

  func run(_ events: [UndoMachine.Event]) -> UndoMachine.State {
    events.reduce(UndoMachine.State()) { UndoMachine.transition($0, $1).0 }
  }

  @Test func undoThenRedoRestoresTheStroke() {
    let state = run([.strokeCommitted(stroke(0.1)), .strokeCommitted(stroke(0.2)), .undo])
    #expect(state.strokes == [stroke(0.1)])
    #expect(state.redoable == [stroke(0.2)])
    #expect(UndoMachine.transition(state, .redo).0.strokes == [stroke(0.1), stroke(0.2)])
  }

  @Test func committingClearsRedo() {
    let state = run([.strokeCommitted(stroke(0.1)), .undo, .strokeCommitted(stroke(0.3))])
    #expect(state.strokes == [stroke(0.3)])
    #expect(state.redoable.isEmpty)
  }

  @Test func undoAndRedoOnEmptyHistoryChangeNothing() {
    #expect(run([.undo, .redo]) == UndoMachine.State())
  }

  @Test func redoesInReverseOrderOfUndo() {
    let state = run([
      .strokeCommitted(stroke(0.1)), .strokeCommitted(stroke(0.2)), .undo, .undo, .redo,
    ])
    #expect(state.strokes == [stroke(0.1)])
  }
}

@Suite struct StrokeRendererTests {
  func pixels(_ strokes: [Stroke]) throws -> (alpha: (Int, Int) -> UInt8, red: (Int, Int) -> UInt8)
  {
    let side = 100
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
      CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    try StrokeRenderer.draw(strokes, in: context, size: CGSize(width: side, height: side))
    let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let buffer = Array(UnsafeBufferPointer(start: data, count: side * side * 4))
    return (
      { x, y in buffer[(y * side + x) * 4 + 3] },
      { x, y in buffer[(y * side + x) * 4] }
    )
  }

  @Test func drawsWithTopLeftOrigin() throws {
    let line = Stroke(
      color: "#FF0000", width: 0.1, points: [Point(x: 0.1, y: 0.25), Point(x: 0.9, y: 0.25)])
    let result = try pixels([line])
    #expect(result.alpha(50, 25) == 255)
    #expect(result.red(50, 25) == 255)
    #expect(result.alpha(50, 75) == 0)
  }

  @Test func singlePointDrawsADot() throws {
    let dot = Stroke(color: "#000000", width: 0.2, points: [Point(x: 0.5, y: 0.5)])
    #expect(try pixels([dot]).alpha(50, 50) == 255)
  }

  @Test func rejectsMalformedColour() {
    let bad = Stroke(color: "red", width: 0.1, points: [Point(x: 0.5, y: 0.5)])
    #expect(throws: InkError.invalidColor("red")) { try pixels([bad]) }
  }
}
