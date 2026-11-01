import Pet

/// How long a scene's own animation of each step runs. Scenes call ``play(_:sleep:onEvent:)`` from
/// `.task(id: world)`, so a world change cancels the wait and no event goes out for an old step.
public struct PetScenePacing: Hashable, Sendable {
  public var delivery: Duration
  public var settling: Duration

  public init(delivery: Duration, settling: Duration) {
    self.delivery = delivery
    self.settling = settling
  }

  public func play(
    _ world: PetWorld,
    sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
    onEvent: @MainActor (PetSceneEvent) -> Void
  ) async {
    switch world.activity {
    case .sleeping:
      return
    case .delivering:
      await sleep(delivery)
      guard !Task.isCancelled else { return }
      await onEvent(.deliveryFinished(delivery: world.delivery))
    case .settling:
      await sleep(settling)
      guard !Task.isCancelled else { return }
      await onEvent(.settled(delivery: world.delivery))
    }
  }
}
