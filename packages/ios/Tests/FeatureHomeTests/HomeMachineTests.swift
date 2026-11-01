import BilletKit
import Pet
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
    #expect(state.pet.world.activity == .sleeping)
  }

  @Test func canvasOpensAndCloses() {
    #expect(apply([.canvasOpened]).screen == .canvas)
    #expect(apply([.canvasOpened, .canvasClosed]).screen == .home)
  }

  @Test func closingTheCanvasDoesNotWakeThePet() {
    #expect(apply([.canvasOpened, .canvasClosed]).pet.world.activity == .sleeping)
  }

  @Test func sendingReturnsHomeAndDeliversTheDrawing() {
    let (state, outputs) = HomeMachine.transition(
      apply([.canvasOpened]), .drawingSent(strokes))
    #expect(state.screen == .home)
    #expect(outputs == [.deliver(strokes)])
    #expect(!state.pet.world.noteArrived)
  }

  @Test func petEventsReachThePetAndItsOutputsComeBack() {
    let (state, outputs) = HomeMachine.transition(HomeMachine.State(), .pet(.noteArrived))
    #expect(state.pet.world.noteArrived)
    #expect(outputs == [.pet(.deliveryDeadline(delivery: 1))])
  }

  @Test func canvasStaysOpenWhileThePetDelivers() {
    let state = apply([.canvasOpened, .pet(.noteArrived)])
    #expect(state.screen == .canvas)
    #expect(state.pet.world.noteArrived)
  }

  @Test @MainActor func storeRunsTheWholeDeliveryWithoutAScene() async {
    let store = Store<HomeMachine>(initial: HomeMachine.State()) {
      await HomeRunner.run($0, delivery: .localFake, sleep: { _ in })
    }
    store.send(.drawingSent(strokes))
    await store.settled()
    #expect(store.state.pet.world == PetWorld(activity: .sleeping, delivery: 1))
  }
}
