import Testing
import Wire

@testable import FeatureCanvas

@Suite struct LiveStrokeBatcherTests {
  static let color = "#7B4FE0"

  private func points(_ frames: [ClientMessage]) -> [[Point]] {
    frames.compactMap {
      if case .strokePoints(_, let points) = $0 { return points }
      return nil
    }
  }

  @Test func aStrokeIsBeginBatchedPointsEnd() {
    var batcher = LiveStrokeBatcher()
    var frames = batcher.begin(color: Self.color, width: 0.03, at: Point(x: 0, y: 0), time: 0)
    #expect(frames == [.strokeBegin(LiveStrokeStart(id: 0, color: Self.color, width: 0.03))])

    // Points within the interval wait; the one past it sends the whole batch.
    #expect(batcher.add(Point(x: 1, y: 1), time: 0.01).isEmpty)
    #expect(batcher.add(Point(x: 2, y: 2), time: 0.02).isEmpty)
    frames = batcher.add(Point(x: 3, y: 3), time: 0.05)
    #expect(points(frames) == [[0, 1, 2, 3].map { Point(x: Double($0), y: Double($0)) }])

    _ = batcher.add(Point(x: 4, y: 4), time: 0.06)
    frames = batcher.end()
    #expect(frames == [.strokePoints(id: 0, points: [Point(x: 4, y: 4)]), .strokeEnd(id: 0)])
  }

  @Test func aFullBatchGoesAtOnce() {
    var batcher = LiveStrokeBatcher()
    _ = batcher.begin(color: Self.color, width: 0.03, at: Point(x: 0, y: 0), time: 0)
    var sent: [[Point]] = []
    for i in 1..<LiveStrokeStart.maxPoints {
      sent += points(batcher.add(Point(x: Double(i), y: 0), time: 0))
    }
    #expect(sent.count == 1)
    #expect(sent.first?.count == LiveStrokeStart.maxPoints)
  }

  @Test func tickSendsTheTailOfASlowFinger() {
    var batcher = LiveStrokeBatcher()
    _ = batcher.begin(color: Self.color, width: 0.03, at: Point(x: 0, y: 0), time: 0)
    #expect(batcher.tick(time: 0.01).isEmpty)
    #expect(points(batcher.tick(time: 0.05)) == [[Point(x: 0, y: 0)]])
    #expect(batcher.tick(time: 0.2).isEmpty)
  }

  @Test func eachStrokeGetsANewIDAndAnOpenOneIsEndedFirst() {
    var batcher = LiveStrokeBatcher()
    _ = batcher.begin(color: Self.color, width: 0.03, at: Point(x: 0, y: 0), time: 0)
    let frames = batcher.begin(color: Self.color, width: 0.03, at: Point(x: 1, y: 1), time: 1)
    #expect(
      frames == [
        .strokePoints(id: 0, points: [Point(x: 0, y: 0)]), .strokeEnd(id: 0),
        .strokeBegin(LiveStrokeStart(id: 1, color: Self.color, width: 0.03)),
      ])
    var fresh = LiveStrokeBatcher()
    #expect(fresh.end().isEmpty)
  }
}
