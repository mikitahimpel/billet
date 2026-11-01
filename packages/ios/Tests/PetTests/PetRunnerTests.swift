import BilletKit
import Pet
import Testing

@Suite("PetRunner")
struct PetRunnerTests {
  @Test func deadlinesResolveToTheirStep() async {
    #expect(
      await PetRunner.run(.deliveryDeadline(delivery: 3), sleep: { _ in })
        == .deliveryFinished(delivery: 3))
    #expect(
      await PetRunner.run(.settlingDeadline(delivery: 3), sleep: { _ in })
        == .settled(delivery: 3))
  }

  @Test @MainActor func hungSceneStillGetsThePetBackToSleep() async {
    let store = Store<PetMachine>(initial: PetMachine.State()) { output in
      await PetRunner.run(output, sleep: { _ in })
    }
    store.send(.noteArrived)
    await store.settled()
    #expect(store.state.world == PetWorld(activity: .sleeping, delivery: 1))
  }
}
