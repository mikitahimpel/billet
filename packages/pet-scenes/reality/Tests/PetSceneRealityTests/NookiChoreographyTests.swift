import Pet
import PetScene
import Testing

@testable import PetSceneReality

@Suite("NookiChoreography")
struct NookiChoreographyTests {
  private func frame(_ activity: PetWorld.Activity, delivery: Int = 1, at elapsed: Double)
    -> NookiFrame
  {
    NookiChoreography.frame(PetWorld(activity: activity, delivery: delivery), elapsed: elapsed)
  }

  private var seconds: (delivery: Double, settling: Double) {
    let pacing = NookiChoreography.pacing
    return (
      Double(pacing.delivery.components.seconds), Double(pacing.settling.components.seconds) + 0.5
    )
  }

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

  @Test func mochiWakesBeforeTheNoteMoves() {
    let awake = frame(.delivering, at: 1.1)
    #expect(awake.wake == 1)
    #expect(awake.eyesOpen)
    #expect(awake.note == 0)
  }

  @Test func noteHasArrivedAndMochiHopsBeforeTheStepEnds() {
    #expect(frame(.delivering, at: 3.8).note == 1)
    #expect(frame(.delivering, at: 4.8).hop > 0.9)
    let last = frame(.delivering, at: seconds.delivery)
    #expect(last.note == 1)
    #expect(last.hop == 0)
    #expect(last.wake == 1)
  }

  @Test func settlingEndsCurledUpWithTheNoteStillHanging() {
    #expect(frame(.settling, at: 0).wake == 1)
    #expect(frame(.settling, at: 0).eyesOpen)
    #expect(frame(.settling, at: seconds.settling) == NookiFrame(note: 1))
  }

  @Test func sleepAfterADeliveryMatchesTheEndOfSettling() {
    #expect(frame(.sleeping, at: 0) == frame(.settling, at: seconds.settling))
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
