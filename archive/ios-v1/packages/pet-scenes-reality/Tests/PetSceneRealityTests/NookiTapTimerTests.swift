import Testing

@testable import PetSceneReality

@Suite struct NookiTapTimerTests {
  @Test func secondTapInsideTheWindowIsADoubleTap() {
    var timer = NookiTapTimer()
    let results = [10, 10.2].map { timer.isDoubleTap(at: $0) }
    #expect(results == [false, true])
  }

  @Test func slowTapsAndAThirdTapStayApart() {
    var timer = NookiTapTimer()
    let results = [10, 11, 11.1, 11.2].map { timer.isDoubleTap(at: $0) }
    #expect(results == [false, false, true, false])
  }
}
