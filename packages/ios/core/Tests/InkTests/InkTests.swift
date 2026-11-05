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
    let size = try InkEncoder.byteCount(compact)
    #expect(size < 3072)
    #expect(compact.strokes.count == 5)
  }

  @Test func sizeShrinksAsToleranceGrows() throws {
    let drawing = referenceDrawing()
    let fine = try InkEncoder.encode(drawing, parameters: .init(tolerance: 0.0005))
    let coarse = try InkEncoder.encode(drawing, parameters: .init(tolerance: 0.01))
    #expect(try InkEncoder.byteCount(coarse) < InkEncoder.byteCount(fine))
  }

  @Test func referenceDrawingFitsTheBudgetAtTheDefaultTolerance() throws {
    // Without `encodeWithinBudget` loosening anything: a regression in how well the default
    // simplification does would show here.
    let compact = try InkEncoder.encode(referenceDrawing())
    #expect(try InkEncoder.byteCount(compact) <= InkEncoder.Parameters().budget)
  }

  @Test func budgetSearchKeepsTheFinestToleranceThatFits() throws {
    let drawing = referenceDrawing()
    let budget = try InkEncoder.byteCount(
      InkEncoder.encode(drawing, parameters: .init(tolerance: 0.004)))
    let fitted = try InkEncoder.encodeWithinBudget(drawing, parameters: .init(budget: budget))
    #expect(try InkEncoder.byteCount(fitted) <= budget)
    let finer = try InkEncoder.encode(drawing, parameters: .init(tolerance: 0.002))
    #expect(try InkEncoder.byteCount(finer) > budget)
  }

  @Test(arguments: [0.0005, 0.002, 0.01, 0.05])
  func simplifiedStrokesStayWithinTheToleranceOfTheOriginal(_ tolerance: Double) {
    for stroke in referenceDrawing() {
      let kept = InkEncoder.simplify(stroke.points, tolerance: tolerance)
      #expect(kept.first == stroke.points.first && kept.last == stroke.points.last)
      for point in stroke.points {
        #expect(distance(from: point, toPolyline: kept) <= tolerance + 1e-12)
      }
    }
  }

  @Test func quantisingAddsAtMostHalfAStepToTheSimplificationError() throws {
    let parameters = InkEncoder.Parameters(tolerance: 0.01)
    let drawing = referenceDrawing()
    let decoded = try InkDecoder.decode(
      InkEncoder.encode(drawing, parameters: parameters), resolution: parameters.resolution)
    let bound = parameters.tolerance + 1 / Double(parameters.resolution)
    for (original, restored) in zip(drawing, decoded) {
      for point in original.points {
        #expect(distance(from: point, toPolyline: restored.points) <= bound)
      }
    }
  }

  private func distance(from point: Point, toPolyline line: [Point]) -> Double {
    guard line.count > 1 else {
      return line.first.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity
    }
    return zip(line, line.dropFirst()).map { a, b in
      let (dx, dy) = (b.x - a.x, b.y - a.y)
      let lengthSquared = dx * dx + dy * dy
      let t =
        lengthSquared == 0
        ? 0 : max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
      return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }.min() ?? .infinity
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

  private func stroke(
    color: String = "#000000", width: Double = 0.01, _ points: [Point]
  ) -> [Stroke] {
    [Stroke(color: color, width: width, points: points)]
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func nonFiniteCoordinatesAreRejected(_ value: Double) {
    #expect(throws: InkError.nonFinite(strokeIndex: 0)) {
      try InkEncoder.encode(stroke([Point(x: value, y: 0.5)]))
    }
    #expect(throws: InkError.nonFinite(strokeIndex: 0)) {
      try InkEncoder.encode(stroke([Point(x: 0.5, y: value)]))
    }
  }

  @Test(arguments: [Double.nan, .infinity])
  func aNonFiniteWidthIsRejected(_ width: Double) {
    #expect(throws: InkError.nonFinite(strokeIndex: 0)) {
      try InkEncoder.encode(stroke(width: width, [Point(x: 0.5, y: 0.5)]))
    }
  }

  @Test func hugeOrNegativeValuesAreRejectedNotTrapped() {
    #expect(throws: InkError.outOfRange(strokeIndex: 0)) {
      try InkEncoder.encode(stroke([Point(x: 1e300, y: 0.5)]))
    }
    #expect(throws: InkError.outOfRange(strokeIndex: 0)) {
      try InkEncoder.encode(stroke(width: 1e300, [Point(x: 0.5, y: 0.5)]))
    }
    #expect(throws: InkError.outOfRange(strokeIndex: 0)) {
      try InkEncoder.encode(stroke(width: -0.01, [Point(x: 0.5, y: 0.5)]))
    }
  }

  @Test func theBadStrokeIsNamedByItsIndex() {
    let strokes = stroke([Point(x: 0.1, y: 0.1)]) + stroke([Point(x: .nan, y: 0.1)])
    #expect(throws: InkError.nonFinite(strokeIndex: 1)) { try InkEncoder.encode(strokes) }
  }

  @Test func theEdgesOfTheAllowedRangeStillEncode() throws {
    let edge = stroke(width: 0, [Point(x: -InkEncoder.limit, y: InkEncoder.limit)])
    #expect(try InkEncoder.encode(edge).strokes.count == 1)
  }

  @Test(arguments: ["red", "#12345", "#1234567", "123456", "#GGGGGG", "#+12345", "# 12345", ""])
  func theEncoderRejectsColoursThatAreNotRRGGBB(_ color: String) {
    #expect(throws: InkError.invalidColor(color)) {
      try InkEncoder.encode(stroke(color: color, [Point(x: 0.5, y: 0.5)]))
    }
  }

  @Test(arguments: ["#000000", "#abcdef", "#ABCDEF", "#0aF9b1"])
  func theEncoderAcceptsEitherCaseOfHexDigits(_ color: String) throws {
    let compact = try InkEncoder.encode(stroke(color: color, [Point(x: 0.5, y: 0.5)]))
    #expect(compact.strokes.first?.color == color)
  }

  @Test(arguments: ["red", "#12345", "#+12345", ""])
  func theDecoderRejectsColoursThatAreNotRRGGBB(_ color: String) {
    let bad = CompactStrokes(strokes: [CompactStroke(color: color, width: 1, points: [1, 2])])
    #expect(throws: InkError.invalidColor(color)) { try InkDecoder.decode(bad) }
  }

  @Test func byteCountReportsASizeForAnyEncodableStrokes() throws {
    let compact = try InkEncoder.encode(referenceDrawing())
    #expect(try InkEncoder.byteCount(compact) > 0)
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
  func pixels(_ strokes: [Stroke], width side: Int = 100, height: Int? = nil) throws -> (
    alpha: (Int, Int) -> UInt8, red: (Int, Int) -> UInt8
  ) {
    let height = height ?? side
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
      CGContext(
        data: nil, width: side, height: height, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    try StrokeRenderer.draw(strokes, in: context, size: CGSize(width: side, height: height))
    let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let buffer = Array(UnsafeBufferPointer(start: data, count: side * height * 4))
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

  @Test func scalesToAnotherSquareSize() throws {
    let line = Stroke(
      color: "#FF0000", width: 0.1, points: [Point(x: 0.1, y: 0.25), Point(x: 0.9, y: 0.25)])
    let result = try pixels([line], width: 200)
    #expect(result.alpha(100, 50) == 255)
    #expect(result.alpha(100, 150) == 0)
    // A tenth of the width is 20 pixels thick here, so 10 pixels either side of the line.
    #expect(result.alpha(100, 42) == 255)
    #expect(result.alpha(100, 62) == 0)
  }

  @Test func bothAxesScaleByTheWidthOnANonSquareCanvas() throws {
    // The contract measures y in widths too, so on 200 x 100 a y of 0.25 is pixel 50 and a y of
    // 0.5 is the bottom edge.
    let dot = Stroke(color: "#FF0000", width: 0.1, points: [Point(x: 0.25, y: 0.25)])
    let result = try pixels([dot], width: 200, height: 100)
    #expect(result.alpha(50, 50) == 255)
    #expect(result.alpha(150, 50) == 0)
    #expect(result.alpha(50, 5) == 0)
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
