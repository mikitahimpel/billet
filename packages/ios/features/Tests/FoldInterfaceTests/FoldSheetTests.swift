import Testing
import Wire

@testable import FoldInterface

private func line(_ points: [(Double, Double)]) -> Stroke {
  Stroke(color: FoldRules.topInk, width: FoldRules.penWidth, points: points.map(Point.init))
}

@Suite struct FoldSheetTests {
  private let line0 = FoldSheet.peekLine

  @Test func theHalvesMeetAtTheFoldAndFillTheSheet() {
    #expect(FoldHalf.top.range.upperBound == FoldHalf.bottom.range.lowerBound)
    #expect(FoldHalf.top.range.lowerBound == 0)
    #expect(FoldHalf.bottom.range.upperBound == 2 * FoldRules.half)
    #expect(FoldRules.peek < FoldRules.half)
  }

  @Test func aPointIsKeptOnTheSheetAndInItsOwnHalf() {
    #expect(FoldHalf.top.kept(Point(x: -0.2, y: 0.9)) == Point(x: 0, y: FoldRules.half))
    #expect(FoldHalf.bottom.kept(Point(x: 1.4, y: 0.1)) == Point(x: 1, y: FoldRules.half))
    #expect(FoldHalf.bottom.kept(Point(x: 0.5, y: 9)) == Point(x: 0.5, y: 2 * FoldRules.half))
    #expect(FoldHalf.top.kept(Point(x: 0.5, y: 0.3)) == Point(x: 0.5, y: 0.3))
  }

  @Test func aTopHalfReachesTheFoldOnlyWhenALineComesIntoTheStrip() {
    #expect(!FoldSheet.reachesFold([]))
    #expect(!FoldSheet.reachesFold([line([(0.2, 0.1), (0.8, line0 - 0.01)])]))
    #expect(FoldSheet.reachesFold([line([(0.2, 0.1)]), line([(0.5, line0)])]))
  }

  @Test func aLineIsCutWhereItCrossesIntoTheStrip() {
    let cut = FoldSheet.cut(
      [Point(x: 0, y: line0 - 0.1), Point(x: 1, y: line0 + 0.1)], below: line0)
    #expect(cut.count == 1)
    #expect(cut[0].count == 2)
    #expect(abs(cut[0][0].x - 0.5) < 1e-9)
    #expect(cut[0][0].y == line0)
    #expect(cut[0][1] == Point(x: 1, y: line0 + 0.1))
  }

  @Test func aLineThatDipsInTwiceGivesTwoRuns() {
    let high = line0 - 0.1
    let low = line0 + 0.02
    let cut = FoldSheet.cut(
      [(0.0, high), (0.1, low), (0.2, high), (0.3, low), (0.4, low)].map(Point.init), below: line0)
    #expect(cut.count == 2)
    #expect(cut[0].count == 3)
    #expect(cut[0].first?.y == line0)
    #expect(cut[0].last?.y == line0)
    #expect(cut[1].count == 3)
    #expect(cut[1].last == Point(x: 0.4, y: low))
  }

  @Test func aLineAboveTheStripLeavesNothingAndOneInsideItStaysWhole() {
    #expect(FoldSheet.cut([Point(x: 0, y: 0), Point(x: 1, y: 0.1)], below: line0).isEmpty)
    let inside = [Point(x: 0, y: line0), Point(x: 1, y: FoldRules.half)]
    #expect(FoldSheet.cut(inside, below: line0) == [inside])
  }

  @Test func thePeekKeepsEachLinesInkAndNothingAboveTheStrip() {
    let peek = FoldSheet.peek(of: [
      line([(0.3, 0.2), (0.3, FoldRules.half)]), line([(0.1, 0.1), (0.9, 0.1)]),
    ])
    #expect(peek.count == 1)
    #expect(peek[0].color == FoldRules.topInk)
    #expect(peek[0].points.allSatisfy { $0.y >= line0 })
  }

  @Test func movingStrokesShiftsEveryPoint() {
    let moved = FoldSheet.moved([line([(0.3, 0.5), (0.4, 0.6)])], by: -0.5)
    #expect(moved[0].points[0].x == 0.3)
    #expect(abs(moved[0].points[0].y) < 1e-9)
    #expect(abs(moved[0].points[1].y - 0.1) < 1e-9)
  }
}

@Suite struct FoldCreatureTests {
  @Test func theSameDrawingAlwaysGetsTheSameName() {
    let top = [line([(0.2, 0.2), (0.5, 0.6)])]
    let bottom = [line([(0.5, 0.7), (0.5, 1.1)])]
    let name = FoldCreature(top: top, bottom: bottom).name
    #expect(name == FoldCreature(top: top, bottom: bottom).name)
    #expect(name.hasPrefix("the "))
    #expect(name.split(separator: " ").count == 3)
  }

  @Test func aFloatsLastBitDoesNotChangeTheName() {
    let a = FoldCreature(top: [line([(0.2, 0.2)])], bottom: [])
    let b = FoldCreature(top: [line([(0.2 + 1e-12, 0.2 - 1e-12)])], bottom: [])
    #expect(FoldCreature.mark(of: a.strokes) == FoldCreature.mark(of: b.strokes))
  }

  @Test func differentDrawingsGetManyDifferentNames() {
    let names = Set(
      (0..<60).map { index in
        FoldCreature(top: [line([(Double(index) / 100, 0.3)])], bottom: []).name
      })
    #expect(names.count > 40)
  }
}
