import Testing

@testable import FeatureCanvas

@Suite struct LivePacerTests {
  @Test func aSteadyStreamIsDrawnAsItArrives() {
    var pacer = LivePacer()
    for frame in 0..<10 {
      let arrived = 5 + Double(frame) * 0.04
      #expect(pacer.draw(relayedAt: 1_000 + frame * 40, arrived: arrived) == arrived)
    }
  }

  @Test func aClumpIsSpreadAtTheRelayPaceAndFaster() {
    var pacer = LivePacer()
    #expect(pacer.draw(relayedAt: 1_000, arrived: 5) == 5)
    // Frames relayed 40 ms apart all arrive together, 300 ms late.
    let times = (1...5).map { pacer.draw(relayedAt: 1_000 + $0 * 40, arrived: 5.34) }
    #expect(times[0] == 5.34)
    for (earlier, later) in zip(times, times.dropFirst()) {
      #expect(abs(later - earlier - 0.04 / LivePacer.catchUp) < 1e-9)
    }
  }

  @Test func noFrameIsHeldPastTheLimit() {
    var pacer = LivePacer()
    _ = pacer.draw(relayedAt: 0, arrived: 0)
    // A long clump: 40 frames arriving at once.
    let times = (1...40).map { pacer.draw(relayedAt: $0 * 40, arrived: 2) }
    #expect(times.allSatisfy { $0 <= 2 + LivePacer.maxLag + 1e-9 })
    #expect(times == times.sorted())
  }

  @Test func theLagDrainsOnceTheStreamIsSteadyAgain() {
    var pacer = LivePacer()
    _ = pacer.draw(relayedAt: 0, arrived: 0)
    for frame in 1...8 { _ = pacer.draw(relayedAt: frame * 40, arrived: 0.33) }
    var lag = 1.0
    for frame in 9...40 {
      let arrived = 0.33 + Double(frame - 8) * 0.04
      lag = pacer.draw(relayedAt: frame * 40, arrived: arrived) - arrived
    }
    #expect(lag < 1e-9)
  }

  @Test func framesWithoutAStampKeepTheirPlace() {
    var pacer = LivePacer()
    _ = pacer.draw(relayedAt: 0, arrived: 0)
    let held = pacer.draw(relayedAt: 40, arrived: 0)
    let begin = pacer.draw(relayedAt: nil, arrived: 0)
    #expect(held > 0)
    #expect(begin == held)
  }

  @Test func aPauseStartsAfresh() {
    var pacer = LivePacer()
    _ = pacer.draw(relayedAt: 0, arrived: 0)
    #expect(pacer.draw(relayedAt: 5_000, arrived: 5) == 5)
  }
}
