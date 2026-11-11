import Testing

@testable import Pet

@Suite struct CatWatchTests {
  @Test func aCatInTheRoomAndDrawnIsLeftAlone() {
    var watch = CatWatch()
    for _ in 0..<600 {
      #expect(watch.update(1.0 / 60, at: [0.1, 0.02, -0.2], isDrawn: true) == .fine)
    }
  }

  @Test func aBadPositionSendsHerHome() {
    let nan = Float.nan
    let bad: [SIMD3<Float>] = [
      [nan, 0, 0], [0, nan, 0], [0, 0, nan], [.infinity, 0, 0], [0, 0, -.infinity],
      [5, 0, 0], [0, 0, 9], [0, -3, 0], [0, 40, 0],
    ]
    for at in bad {
      var watch = CatWatch()
      #expect(watch.update(0.016, at: at, isDrawn: true) == .snapHome)
    }
  }

  @Test func aCatNotDrawnForTheWholeWaitIsShownAgainAndTheWaitStartsOver() {
    var watch = CatWatch(patience: 2)
    var verdicts: [CatWatch.Verdict] = []
    for _ in 0..<5 { verdicts.append(watch.update(1, at: [0, 0.02, 0], isDrawn: false)) }
    #expect(verdicts == [.fine, .showAgain, .fine, .showAgain, .fine])
  }

  @Test func beingDrawnAgainClearsTheWait() {
    var watch = CatWatch(patience: 2)
    #expect(watch.update(1.5, at: [0, 0.02, 0], isDrawn: false) == .fine)
    #expect(watch.update(0.1, at: [0, 0.02, 0], isDrawn: true) == .fine)
    #expect(watch.update(1.5, at: [0, 0.02, 0], isDrawn: false) == .fine)
  }
}
