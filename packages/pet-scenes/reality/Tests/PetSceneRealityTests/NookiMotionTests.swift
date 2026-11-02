import Testing

@testable import PetSceneReality

@Suite("NookiMotion")
struct NookiMotionTests {
  private let times = stride(from: 0.0, to: 30.0, by: 0.05).map { $0 }

  @Test func reduceMotionStillsEveryIdleLoop() {
    for time in times {
      #expect(NookiMotion.flicker(time, reduceMotion: true) == 1)
      #expect(NookiMotion.sway(time, reduceMotion: true) == 0)
      #expect(NookiMotion.wobble(time, reduceMotion: true) == 0)
    }
  }

  @Test func reduceMotionKeepsOnlyTheEyesOfAPet() {
    let frame = NookiMotion.pet(0.5, reduceMotion: true)
    #expect(frame == NookiFrame(eyesOpen: true))
  }

  @Test func flickerStaysGentle() {
    for time in times {
      #expect(abs(NookiMotion.flicker(time, reduceMotion: false) - 1) < 0.08)
    }
  }

  @Test func wobbleDiesAwayToNothing() {
    #expect(NookiMotion.wobble(NookiMotion.wobbleLength, reduceMotion: false) == 0)
    #expect(abs(NookiMotion.wobble(0.1, reduceMotion: false)) < 0.05)
  }

  @Test func petEndsWhereItBegan() {
    #expect(NookiMotion.pet(NookiMotion.petLength, reduceMotion: false) == NookiFrame())
  }

  @Test func petReactionLeavesTheDeliveryUnderneathAlone() {
    let delivery = NookiFrame(wake: 1, note: 1, pinned: 0.5, walk: 0.5)
    let combined = delivery.combined(with: NookiMotion.pet(0.5, reduceMotion: false))
    #expect(combined.walk == 0.5)
    #expect(combined.pinned == 0.5)
    #expect(combined.wake == 1)
  }
}
