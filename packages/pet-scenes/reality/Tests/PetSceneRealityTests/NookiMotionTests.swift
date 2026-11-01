import Testing

@testable import PetSceneReality

@Suite("NookiMotion")
struct NookiMotionTests {
  private let times = stride(from: 0.0, to: 30.0, by: 0.05).map { $0 }

  @Test func reduceMotionStillsEveryIdleLoop() {
    for time in times {
      #expect(NookiMotion.blink(time, reduceMotion: true) == 1)
      #expect(NookiMotion.earTwitch(time, ear: 0, reduceMotion: true) == 0)
      #expect(NookiMotion.bellSwing(time, energy: 1, reduceMotion: true) == 0)
      #expect(NookiMotion.flicker(time, reduceMotion: true) == 1)
      #expect(NookiMotion.sway(time, reduceMotion: true) == 0)
      #expect(NookiMotion.yarnDrift(time, reduceMotion: true) == 0)
      #expect(NookiMotion.wobble(time, reduceMotion: true) == 0)
    }
  }

  @Test func reduceMotionKeepsOnlyTheEyesOfAPet() {
    let frame = NookiMotion.pet(0.5, reduceMotion: true)
    #expect(frame == NookiFrame(eyesOpen: true))
  }

  @Test func blinksAreBriefAndRegular() {
    let shut = times.filter { NookiMotion.blink($0, reduceMotion: false) < 1 }.count
    #expect(shut > 0)
    #expect(Double(shut) / Double(times.count) < 0.1)
  }

  @Test func earsTwitchOutOfStep() {
    let left = times.filter { NookiMotion.earTwitch($0, ear: 0, reduceMotion: false) != 0 }
    let right = times.filter { NookiMotion.earTwitch($0, ear: 1, reduceMotion: false) != 0 }
    #expect(!left.isEmpty)
    #expect(Set(left).isDisjoint(with: right))
  }

  @Test func bellSwingsMoreWhenMochiMoves() {
    let still = times.map { abs(NookiMotion.bellSwing($0, energy: 0, reduceMotion: false)) }
    let moving = times.map { abs(NookiMotion.bellSwing($0, energy: 1, reduceMotion: false)) }
    #expect(moving.max()! > still.max()! * 3)
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
