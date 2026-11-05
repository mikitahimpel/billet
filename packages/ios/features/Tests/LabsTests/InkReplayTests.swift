import Foundation
import Testing
import Wire

@testable import Labs

@Suite struct InkReplayTests {
  private func line(_ from: Double, _ to: Double, color: String = "#112233") -> Stroke {
    Stroke(color: color, width: 0.01, points: [Point(x: from, y: 0.5), Point(x: to, y: 0.5)])
  }

  private var two: [Stroke] { [line(0, 0.4, color: "#AA0000"), line(0.5, 0.9, color: "#00AA00")] }

  @Test func nothingIsDrawnAtTheStartAndEverythingAtTheEnd() {
    #expect(InkReplay.strokes(of: two, progress: 0).isEmpty)
    #expect(InkReplay.strokes(of: two, progress: 1) == two)
    #expect(InkReplay.strokes(of: two, progress: 4) == two)
  }

  @Test func strokesAppearInTheOrderTheyWereDrawn() {
    let half = InkReplay.strokes(of: two, progress: 0.25)
    #expect(half.count == 1)
    #expect(half[0].color == "#AA0000")
    let past = InkReplay.strokes(of: two, progress: 0.75)
    #expect(past.map(\.color) == ["#AA0000", "#00AA00"])
  }

  @Test func theStrokeInProgressIsCutAtThePen() throws {
    let cut = try #require(InkReplay.strokes(of: two, progress: 0.25).first)
    let end = try #require(cut.points.last)
    #expect(abs(end.x - 0.2) < 1e-9)
  }

  @Test func inkNeverShrinksAsTimePasses() {
    var count = 0
    for step in 0...20 {
      let shown = InkReplay.strokes(of: two, progress: Double(step) / 20)
      let points = shown.reduce(0) { $0 + $1.points.count }
      #expect(points >= count)
      count = points
    }
  }

  @Test func theDurationStaysBetweenItsBounds() {
    #expect(InkReplay.duration(of: []) == InkReplay.shortest)
    let long = (0..<40).map { _ in line(0, 1) }
    #expect(InkReplay.duration(of: long) == InkReplay.longest)
    #expect((InkReplay.shortest...InkReplay.longest).contains(InkReplay.duration(of: two)))
  }

  @Test func aSingleDotIsShownOnceReplayHasStarted() {
    let dot = [Stroke(color: "#000000", width: 0.02, points: [Point(x: 0.5, y: 0.5)])]
    #expect(InkReplay.strokes(of: dot, progress: 0.5) == dot)
  }
}
