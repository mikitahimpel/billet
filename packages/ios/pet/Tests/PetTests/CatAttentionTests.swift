import Pet
import Testing

@Suite("CatAttention")
struct CatAttentionTests {
  private typealias State = CatAttention.State

  private func sound(_ salience: Double, bearing: Double = 1, hold: Double = 2) -> CatStimulus {
    CatStimulus(.sound, .heard, bearing: bearing, salience: salience, hold: hold)
  }

  private func sight(_ source: CatStimulus.Source, _ salience: Double, hold: Double = 2)
    -> CatStimulus
  {
    CatStimulus(source, .seen, bearing: 0.3, salience: salience, hold: hold)
  }

  private func step(_ state: State, _ event: CatAttention.Event) -> State {
    CatAttention.transition(state, event).0
  }

  @Test func aFaintThingIsNotWorthAnEar() {
    #expect(step(.free, .noticed(sound(0.1), at: 0)) == .free)
  }

  @Test func aSoftSoundTurnsAnEarAndNeverTheHead() {
    let pricked = step(.free, .noticed(sound(0.3), at: 1))
    #expect(pricked == .pricked(sound(0.3), since: 1, turns: false))
    #expect(step(pricked, .time(1.5)) == pricked)
    #expect(step(pricked, .time(1.01 + CatAttention.earDwell)) == .free)
  }

  @Test func theEarsLeadTheHeadToASound() {
    let loud = sound(0.8)
    let pricked = step(.free, .noticed(loud, at: 0))
    let lead = CatAttention.earLead(loud)
    #expect(lead > 0.1)
    #expect(step(pricked, .time(lead - 0.01)) == pricked)
    let (watching, outputs) = CatAttention.transition(pricked, .time(lead))
    #expect(watching == .watching(loud, since: lead))
    #expect(outputs == [.turned(loud)])
  }

  @Test func theLouderTheSoundTheSoonerTheHead() {
    #expect(CatAttention.earLead(sound(0.9)) < CatAttention.earLead(sound(0.45)))
  }

  @Test func aSightTurnsTheHeadWithNoWait() {
    let seen = sight(.viewer, 0.6)
    let pricked = step(.free, .noticed(seen, at: 3))
    #expect(step(pricked, .time(3)) == .watching(seen, since: 3))
  }

  @Test func sheLetsGoWithABlinkWhenTheHoldIsOver() {
    let seen = sight(.viewer, 0.6, hold: 2)
    let watching = State.watching(seen, since: 0)
    #expect(step(watching, .time(1.9)) == watching)
    let (releasing, outputs) = CatAttention.transition(watching, .time(2))
    #expect(releasing == .releasing(seen, since: 2))
    #expect(outputs == [.released(seen)])
    #expect(step(releasing, .time(2.3)) == releasing)
    #expect(step(releasing, .time(2 + CatAttention.letGo)) == .free)
  }

  @Test func onlySomethingThatMattersMoreTakesHerOff() {
    let watching = State.watching(sight(.place("sill"), 0.6, hold: 4), since: 0)
    #expect(step(watching, .noticed(sound(0.5), at: 0.5)) == watching)
    #expect(
      step(watching, .noticed(sound(0.9), at: 0.5)) == .pricked(sound(0.9), since: 0.5, turns: true)
    )
  }

  @Test func herInterestWearsOffSoALaterThingWinsMoreEasily() {
    let watching = State.watching(sight(.place("sill"), 0.6, hold: 4), since: 0)
    #expect(
      step(watching, .noticed(sound(0.5), at: 3.9)) == .pricked(sound(0.5), since: 3.9, turns: true)
    )
  }

  @Test func aSoundNotWorthTheHeadNeverBreaksAStare() {
    let watching = State.watching(sight(.place("sill"), 0.2, hold: 4), since: 0)
    #expect(step(watching, .noticed(sound(0.35), at: 3.9)) == watching)
  }

  @Test func theSameThingAgainKeepsHerOnItWithoutStartingOver() {
    let watching = State.watching(sight(.touch, 0.7), since: 1)
    var moved = sight(.touch, 0.5)
    moved.bearing = -0.2
    guard case .watching(let kept, let since) = step(watching, .noticed(moved, at: 1.2)) else {
      Issue.record("not watching")
      return
    }
    #expect(since == 1)
    #expect(kept.bearing == -0.2)
    #expect(kept.salience > 0.5)
  }

  @Test func sheFollowsWhatSheWatchesAndNothingElse() {
    let watching = State.watching(sight(.touch, 0.7), since: 1)
    guard
      case .watching(let moved, _) = step(watching, .moved(.touch, bearing: -0.4, elevation: 0.1))
    else {
      Issue.record("not watching")
      return
    }
    #expect(moved.bearing == -0.4)
    #expect(moved.elevation == 0.1)
    #expect(step(watching, .moved(.viewer, bearing: 1, elevation: 0)) == watching)
  }

  @Test func whatSheWatchesGoingAwayReleasesHer() {
    let seen = sight(.touch, 0.7)
    let (state, outputs) = CatAttention.transition(
      .watching(seen, since: 1), .gone(.touch, at: 1.5))
    #expect(state == .releasing(seen, since: 1.5))
    #expect(outputs == [.released(seen)])
    #expect(step(.watching(seen, since: 1), .gone(.viewer, at: 1.5)) == .watching(seen, since: 1))
    #expect(step(.pricked(seen, since: 1, turns: true), .gone(.touch, at: 1.1)) == .free)
  }

  @Test func eventsWithNothingToActOnChangeNothing() {
    let releasing = State.releasing(sight(.viewer, 0.6), since: 0)
    for state in [State.free, releasing] {
      #expect(step(state, .moved(.viewer, bearing: 1, elevation: 0)) == state)
      #expect(step(state, .gone(.viewer, at: 0.1)) == state)
    }
    #expect(step(.free, .time(100)) == .free)
    let pricked = State.pricked(sound(0.8), since: 0, turns: true)
    #expect(
      step(pricked, .noticed(sound(0.5, bearing: -1), at: 0.05))
        == .pricked(sound(0.5, bearing: -1), since: 0.05, turns: true))
    #expect(step(pricked, .noticed(sight(.viewer, 0.5), at: 0.05)) == pricked)
    #expect(step(pricked, .moved(.viewer, bearing: 0, elevation: 0)) == pricked)
    #expect(step(pricked, .gone(.viewer, at: 0.05)) == pricked)
  }

  @Test func lettingGoSheCanStillBeCaughtBySomething() {
    let releasing = State.releasing(sight(.viewer, 0.6), since: 0)
    #expect(
      step(releasing, .noticed(sound(0.6), at: 0.2))
        == .pricked(sound(0.6), since: 0.2, turns: true))
  }
}
