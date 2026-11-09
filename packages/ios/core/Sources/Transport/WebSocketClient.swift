import BilletKit
import Wire

/// Releasing the client closes its socket and stops its work; `disconnect()` is the orderly stop.
@MainActor
public final class WebSocketClient {
  private let store: Store<WebSocketMachine>
  private let pump: Task<Void, Never>
  private let runner: WebSocketRunner

  public var state: WebSocketMachine.State { store.state }

  /// - Parameter lastSeq: The last note `seq` already held, so the first connection asks only for
  ///   what is newer.
  public init(dependencies: WebSocketDependencies, lastSeq: Int? = nil) {
    let runner = WebSocketRunner(dependencies: dependencies)
    self.runner = runner
    let store = Store<WebSocketMachine>(
      initial: WebSocketMachine.State(phase: .idle, lastSeq: lastSeq, attempt: 0)
    ) { output in
      await runner.run(output)
    }
    self.store = store
    self.pump = Task { @MainActor [weak store] in
      for await event in runner.events {
        store?.send(event)
      }
    }
  }

  deinit {
    pump.cancel()
    let runner = runner
    Task { await runner.shutdown() }
  }

  public func connect() {
    store.send(.connectRequested)
  }

  public func disconnect() {
    store.send(.disconnectRequested)
  }

  /// Dropped, not queued, while not connected. Queued here rather than as a machine output,
  /// since outputs run in their own tasks and can overtake each other.
  public func send(_ message: ClientMessage) {
    let state = store.state
    guard case .connected = state.phase else { return }
    runner.enqueue(message, attempt: state.attempt)
  }

  public func settled() async {
    await store.settled()
  }
}
