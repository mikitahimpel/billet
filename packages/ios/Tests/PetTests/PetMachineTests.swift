import Pet
import Testing

@Suite("PetMachine")
struct PetMachineTests {
  private typealias Event = PetMachine.Event

  private func apply(_ events: [Event]) -> PetMachine.State {
    events.reduce(PetMachine.State()) { PetMachine.transition($0, $1).0 }
  }

  @Test func startsAsleepWithNoNote() {
    let state = PetMachine.State()
    #expect(state.world.activity == .sleeping)
    #expect(!state.world.noteArrived)
  }

  @Test func noteWakesThePetAndStartsADeadline() {
    let (state, outputs) = PetMachine.transition(PetMachine.State(), .noteArrived)
    #expect(state.world.noteArrived)
    #expect(state.world.delivery == 1)
    #expect(outputs == [.deliveryDeadline(delivery: 1)])
  }

  @Test func finishedDeliverySettlesWithItsOwnDeadline() {
    let (state, outputs) = PetMachine.transition(
      apply([.noteArrived]), .deliveryFinished(delivery: 1))
    #expect(state.world.activity == .settling)
    #expect(!state.world.noteArrived)
    #expect(outputs == [.settlingDeadline(delivery: 1)])
  }

  @Test func settledPetSleepsAndPlaysTheNextNoteFromSleep() {
    let asleep = apply([.noteArrived, .deliveryFinished(delivery: 1), .settled(delivery: 1)])
    #expect(asleep.world == PetWorld(activity: .sleeping, delivery: 1))
    let (state, outputs) = PetMachine.transition(asleep, .noteArrived)
    #expect(state.world == PetWorld(activity: .delivering, delivery: 2))
    #expect(outputs == [.deliveryDeadline(delivery: 2)])
  }

  @Test func notesWhileBusyWaitTheirTurn() {
    let busy = apply([.noteArrived, .noteArrived])
    #expect(busy.waitingNotes == 1)
    let settling = apply([.noteArrived, .deliveryFinished(delivery: 1), .noteArrived])
    #expect(settling.waitingNotes == 1)
    #expect(!settling.world.noteArrived)
  }

  @Test func waitingNotePlaysAfterSettling() {
    let (state, outputs) = PetMachine.transition(
      apply([.noteArrived, .noteArrived, .deliveryFinished(delivery: 1)]), .settled(delivery: 1))
    #expect(state.world == PetWorld(activity: .delivering, delivery: 2))
    #expect(state.waitingNotes == 0)
    #expect(outputs == [.deliveryDeadline(delivery: 2)])
  }

  @Test func eventsOutOfTurnAreIgnored() {
    #expect(apply([.deliveryFinished(delivery: 0), .settled(delivery: 0)]) == PetMachine.State())
    let delivering = apply([.noteArrived])
    #expect(PetMachine.transition(delivering, .settled(delivery: 1)).0 == delivering)
  }

  @Test func staleDeadlineCannotCutTheNextDeliveryShort() {
    let second = apply([
      .noteArrived, .noteArrived, .deliveryFinished(delivery: 1), .settled(delivery: 1),
    ])
    #expect(second.world.delivery == 2)
    let (state, outputs) = PetMachine.transition(second, .deliveryFinished(delivery: 1))
    #expect(state == second)
    #expect(outputs.isEmpty)
  }

  @Test func staleSettlingDeadlineCannotWakeANewerSettle() {
    let settlingSecond = apply([
      .noteArrived, .noteArrived, .deliveryFinished(delivery: 1), .settled(delivery: 1),
      .deliveryFinished(delivery: 2),
    ])
    #expect(PetMachine.transition(settlingSecond, .settled(delivery: 1)).0 == settlingSecond)
  }

  @Test func partnerPresenceLightsTheWindowWithoutTouchingTheDelivery() {
    let delivering = apply([.noteArrived])
    let (here, outputs) = PetMachine.transition(delivering, .partnerPresence(true))
    #expect(here.world.partnerHere)
    #expect(here.world.step == delivering.world.step)
    #expect(outputs.isEmpty)
    #expect(!PetMachine.transition(here, .partnerPresence(false)).0.world.partnerHere)
  }

  @Test func partnerStaysHereAcrossDeliverySteps() {
    let state = apply([
      .partnerPresence(true), .noteArrived, .deliveryFinished(delivery: 1), .settled(delivery: 1),
    ])
    #expect(state.world.partnerHere)
    #expect(state.world.activity == .sleeping)
  }

  @Test func streakIsKeptThroughDeliveriesAndNeverNegative() {
    let state = apply([
      .streakChanged(4), .noteArrived, .deliveryFinished(delivery: 1), .settled(delivery: 1),
    ])
    #expect(state.world.streak == 4)
    #expect(apply([.streakChanged(-2)]).world.streak == 0)
    let (same, outputs) = PetMachine.transition(state, .streakChanged(4))
    #expect(same == state)
    #expect(outputs.isEmpty)
  }

  @Test func streakDoesNotChangeTheStep() {
    let delivering = apply([.noteArrived])
    #expect(
      PetMachine.transition(delivering, .streakChanged(9)).0.world.step == delivering.world.step)
  }
}
