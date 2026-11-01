import Pet
import PetScene
import Testing

@testable import PetSceneReality

@Suite("NookiChoreography")
struct NookiChoreographyTests {
  private func frame(
    _ activity: PetWorld.Activity, delivery: Int = 1, at elapsed: Double,
    reduceMotion: Bool = false
  ) -> NookiFrame {
    NookiChoreography.frame(
      PetWorld(activity: activity, delivery: delivery), elapsed: elapsed,
      reduceMotion: reduceMotion)
  }

  private let deliveryEnd = 9.0
  private let settlingEnd = 2.5

  @Test func pacingStaysInsideThePetDeadlines() {
    #expect(NookiChoreography.pacing.delivery < PetRunner.deliveryDeadline)
    #expect(NookiChoreography.pacing.settling < PetRunner.settlingDeadline)
  }

  @Test func asleepBeforeAnyNote() {
    #expect(frame(.sleeping, delivery: 0, at: 5) == NookiFrame())
  }

  @Test func deliveryStartsCurledUpWithTheNoteOutOfSight() {
    #expect(frame(.delivering, at: 0) == NookiFrame())
  }

  @Test func mochiWakesWithMouthOpenBeforeSettingOff() {
    let awake = frame(.delivering, at: 1.1)
    #expect(awake.wake == 1)
    #expect(awake.eyesOpen)
    #expect(awake.mouth > 0.9)
    #expect(awake.walk == 0)
  }

  @Test func noteRidesTheHopWalkToTheWire() {
    let midWalk = frame(.delivering, at: 2.3)
    #expect(midWalk.note == 1)
    #expect(midWalk.pinned == 0)
    #expect(midWalk.walk > 0.4 && midWalk.walk < 0.6)
    let atWall = frame(.delivering, at: 3.9)
    #expect(atWall.walk == 1)
    #expect(atWall.pinned > 0.9)
  }

  @Test func eachStepOfTheWalkSquashesOnLandingAndStretchesInTheAir() {
    let inAir = frame(.delivering, at: 1.2 + 2.2 * 0.5 / 5)
    #expect(inAir.stepHeight > 0.99)
    #expect(inAir.stretch > 0.99)
    let landing = frame(.delivering, at: 1.2 + 2.2 * 1.001 / 5)
    #expect(landing.stepHeight < 0.05)
    #expect(landing.stretch < -0.9)
  }

  @Test func happyHopComesOnceTheNoteHangs() {
    let hop = frame(.delivering, at: 4.4)
    #expect(hop.hop > 0.9)
    #expect(hop.pinned == 1)
  }

  @Test func mochiIsBackInTheBedBeforeTheStepEnds() {
    let last = frame(.delivering, at: deliveryEnd)
    #expect(last.walk == 0)
    #expect(last.stepHeight == 0)
    #expect(last.hop == 0)
    #expect(last.wake == 1)
    #expect(last.pinned == 1)
  }

  @Test func settlingEndsCurledUpWithTheNoteStillHanging() {
    #expect(frame(.settling, at: 0).wake == 1)
    #expect(frame(.settling, at: 0).eyesOpen)
    #expect(frame(.settling, at: settlingEnd) == NookiFrame(note: 1, pinned: 1))
  }

  @Test func sleepAfterADeliveryMatchesTheEndOfSettling() {
    #expect(frame(.sleeping, at: 0) == frame(.settling, at: settlingEnd))
  }

  @Test(arguments: Array(stride(from: 0.0, through: 9.0, by: 0.25)))
  func reduceMotionNeverLeavesTheBed(elapsed: Double) {
    let still = frame(.delivering, at: elapsed, reduceMotion: true)
    #expect(still.walk == 0)
    #expect(still.stepHeight == 0)
    #expect(still.stretch == 0)
    #expect(still.hop == 0)
    #expect(still.note == still.pinned)
  }

  @Test func reduceMotionStillDeliversTheNote() {
    #expect(frame(.delivering, at: 2, reduceMotion: true).pinned == 1)
  }

  @Test func windowLightFollowsThePartnerInEveryStep() {
    for activity in [PetWorld.Activity.sleeping, .delivering, .settling] {
      let here = NookiChoreography.frame(
        PetWorld(activity: activity, delivery: 1, partnerHere: true), elapsed: 2)
      let away = NookiChoreography.frame(PetWorld(activity: activity, delivery: 1), elapsed: 2)
      #expect(here.light == 1)
      #expect(away.light == 0)
      var rest = here
      rest.light = 0
      #expect(rest == away)
    }
  }
}
