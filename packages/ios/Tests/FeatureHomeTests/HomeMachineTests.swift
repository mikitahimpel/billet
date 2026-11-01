import BilletKit
import Testing
import Wire

@testable import FeatureHome

@Suite("HomeMachine")
struct HomeMachineTests {
  private func apply(_ events: [HomeMachine.Event]) -> HomeMachine.State {
    events.reduce(HomeMachine.State()) { HomeMachine.transition($0, $1).0 }
  }

  private let strokes = [Stroke(color: "#000000", width: 2, points: [Point(x: 0.1, y: 0.1)])]

  @Test func startsAsleepOnHome() {
    let state = HomeMachine.State()
    #expect(state.screen == .home)
    #expect(state.cat == .sleeping)
    #expect(!state.noteArrived)
  }

  @Test func canvasOpensAndCloses() {
    #expect(apply([.canvasOpened]).screen == .canvas)
    #expect(apply([.canvasOpened, .canvasClosed]).screen == .home)
  }

  @Test func closingTheCanvasDoesNotWakeTheCat() {
    #expect(apply([.canvasOpened, .canvasClosed]).cat == .sleeping)
  }

  @Test func sendingReturnsHomeAndDeliversTheDrawing() {
    let (state, outputs) = HomeMachine.transition(
      apply([.canvasOpened]), .drawingSent(strokes))
    #expect(state.screen == .home)
    #expect(outputs == [.deliver(strokes)])
    #expect(!state.noteArrived)
  }

  @Test func arrivalSetsNoteArrivedAndHoldsTheDelivery() {
    let (state, outputs) = HomeMachine.transition(HomeMachine.State(), .noteArrived)
    #expect(state.noteArrived)
    #expect(outputs == [.holdDelivery])
  }

  @Test func playedDeliveryResetsNoteArrived() {
    let (state, outputs) = HomeMachine.transition(apply([.noteArrived]), .deliveryPlayed)
    #expect(!state.noteArrived)
    #expect(state.cat == .settling)
    #expect(outputs == [.holdSettling])
  }

  @Test func secondNotePlaysAgainAfterTheFirst() {
    let asleep = apply([.noteArrived, .deliveryPlayed, .settlingPlayed])
    #expect(asleep.cat == .sleeping)
    let (state, outputs) = HomeMachine.transition(asleep, .noteArrived)
    #expect(state.noteArrived)
    #expect(outputs == [.holdDelivery])
  }

  @Test func noteDuringDeliveryWaitsItsTurn() {
    let busy = apply([.noteArrived, .noteArrived])
    #expect(busy.waitingNotes == 1)
    let settling = HomeMachine.transition(busy, .deliveryPlayed).0
    #expect(!settling.noteArrived)
    let (state, outputs) = HomeMachine.transition(settling, .settlingPlayed)
    #expect(state.noteArrived)
    #expect(state.waitingNotes == 0)
    #expect(outputs == [.holdDelivery])
  }

  @Test func noteDuringSettlingWaitsItsTurn() {
    let state = apply([.noteArrived, .deliveryPlayed, .noteArrived])
    #expect(state.cat == .settling)
    #expect(!state.noteArrived)
    #expect(state.waitingNotes == 1)
  }

  @Test func lateHoldsAreIgnored() {
    #expect(apply([.deliveryPlayed, .settlingPlayed]) == HomeMachine.State())
    let delivering = apply([.noteArrived])
    #expect(HomeMachine.transition(delivering, .settlingPlayed).0 == delivering)
  }

  @Test @MainActor func storeRunsTheWholeDelivery() async {
    let store = Store<HomeMachine>(initial: HomeMachine.State()) {
      await HomeRunner.run($0, delivery: .localFake, sleep: { _ in })
    }
    store.send(.drawingSent(strokes))
    await store.settled()
    #expect(store.state == HomeMachine.State(cat: .sleeping))
  }
}
