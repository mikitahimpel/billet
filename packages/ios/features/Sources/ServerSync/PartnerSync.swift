import BilletKit

/// Runs ``PartnerSyncMachine``: the shell says when the app comes to the front or leaves it, when
/// the pair changes and when the room's socket opens; the checks and pulls are its own.
@MainActor
public final class PartnerSync {
  public struct Dependencies {
    public var follow: @MainActor () -> Void
    public var unfollow: @MainActor () -> Void
    /// Whether the room's socket was heard from within `quietLimit`, or else answers a ping.
    public var isHealthy: @MainActor (_ quietLimit: Duration) async -> Bool
    public var pull: @MainActor (PartnerSyncMachine.Kind) async -> Void
    public var sleep: @Sendable (Duration) async -> Void

    public init(
      follow: @escaping @MainActor () -> Void, unfollow: @escaping @MainActor () -> Void,
      isHealthy: @escaping @MainActor (_ quietLimit: Duration) async -> Bool,
      pull: @escaping @MainActor (PartnerSyncMachine.Kind) async -> Void,
      sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
      self.follow = follow
      self.unfollow = unfollow
      self.isHealthy = isHealthy
      self.pull = pull
      self.sleep = sleep
    }
  }

  private let store: Store<PartnerSyncMachine>

  public var state: PartnerSyncMachine.State { store.state }

  public init(_ dependencies: Dependencies) {
    store = Store(initial: .initial) { @MainActor output in
      switch output {
      case .follow:
        dependencies.follow()
        return nil
      case .unfollow:
        dependencies.unfollow()
        return nil
      case .pull(let id, let kind):
        await dependencies.pull(kind)
        return .pulled(id)
      case .tick(let clock, let delay):
        await dependencies.sleep(delay)
        return .ticked(clock: clock)
      case .check(let clock):
        let healthy = await dependencies.isHealthy(PartnerSyncMachine.quietLimit)
        return .checked(clock: clock, healthy: healthy)
      }
    }
  }

  public func send(_ event: PartnerSyncMachine.Event) { store.send(event) }

  /// Returns once no follow, check, pull or tick is running.
  func settled() async { await store.settled() }
}
