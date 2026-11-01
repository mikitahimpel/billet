import BilletKit
import Wire

/// Runs ``WebSocketMachine`` against the given services.
@MainActor
public final class WebSocketClient {
  private let store: Store<WebSocketMachine>
  private let pump: Task<Void, Never>

  public var state: WebSocketMachine.State { store.state }

  public init(dependencies: WebSocketDependencies) {
    let runner = WebSocketRunner(dependencies: dependencies)
    let store = Store<WebSocketMachine>(initial: .initial) { output in
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
  }

  public func connect() {
    store.send(.connectRequested)
  }

  public func disconnect() {
    store.send(.disconnectRequested)
  }

  /// Sends while connected. Otherwise the message is dropped, not queued.
  public func send(_ message: ClientMessage) {
    store.send(.sendRequested(message))
  }

  public func settled() async {
    await store.settled()
  }
}
