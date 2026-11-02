import Pet
import PetScene
import Testing

@Suite("PetScenePacing")
struct PetScenePacingTests {
  private let pacing = PetScenePacing(delivery: .seconds(3), settling: .seconds(1))

  @MainActor private func events(for world: PetWorld) async -> [PetSceneEvent] {
    var events: [PetSceneEvent] = []
    await pacing.play(world, sleep: { _ in }, onEvent: { events.append($0) })
    return events
  }

  @Test @MainActor func sleepingReportsNothing() async {
    #expect(await events(for: PetWorld()).isEmpty)
  }

  @Test @MainActor func reportsTheStepItPlayedWithItsDelivery() async {
    #expect(
      await events(for: PetWorld(activity: .delivering, delivery: 4))
        == [.deliveryFinished(delivery: 4)])
    #expect(
      await events(for: PetWorld(activity: .settling, delivery: 4)) == [.settled(delivery: 4)])
  }

  @Test @MainActor func cancelledStepStaysSilent() async {
    let pacing = pacing
    let task = Task { @MainActor in
      var events: [PetSceneEvent] = []
      await pacing.play(
        PetWorld(activity: .delivering, delivery: 1),
        sleep: { _ in withUnsafeCurrentTask { $0?.cancel() } },
        onEvent: { events.append($0) }
      )
      return events
    }
    #expect(await task.value.isEmpty)
  }

  @Test func sceneEventsMapToPetEvents() {
    #expect(PetMachine.Event(.deliveryFinished(delivery: 2)) == .deliveryFinished(delivery: 2))
    #expect(PetMachine.Event(.settled(delivery: 2)) == .settled(delivery: 2))
  }

  @Test func hostEventsAreNotPetEvents() {
    #expect(PetMachine.Event(.petted) == nil)
    #expect(PetMachine.Event(.noteOpened(delivery: 2)) == nil)
  }
}
