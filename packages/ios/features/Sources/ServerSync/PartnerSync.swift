import BilletKit

/// Runs ``PartnerSyncMachine``: the shell says when the app comes to the front or leaves it and
/// when the pair changes; the room's socket and the pulls are its own.
@MainActor
public final class PartnerSync {
  public struct Dependencies {
    public var follow: @MainActor () -> Void
    public var unfollow: @MainActor () -> Void
    /// Everything the socket may have missed, read from the server.
    public var pull: @MainActor () async -> Void
    public var sleep: @Sendable (Duration) async -> Void

    public init(
      follow: @escaping @MainActor () -> Void, unfollow: @escaping @MainActor () -> Void,
      pull: @escaping @MainActor () async -> Void,
      sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
      self.follow = follow
      self.unfollow = unfollow
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
      case .pull(let id):
        await dependencies.pull()
        return .pulled(id)
      case .tick(let clock):
        await dependencies.sleep(PartnerSyncMachine.every)
        return .ticked(clock: clock)
      }
    }
  }

  public func send(_ event: PartnerSyncMachine.Event) { store.send(event) }

  /// Returns once no follow, pull or tick is running.
  func settled() async { await store.settled() }
}
