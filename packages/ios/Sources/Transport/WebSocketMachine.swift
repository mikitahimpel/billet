import BilletKit
import Wire

/// The connection to the pair's room as an explicit state machine.
///
/// `Store` neither correlates a result with its output nor cancels work, so this machine does both
/// itself. Every connection attempt has an `attempt` number, and every event from a socket or timer
/// carries the number it belongs to. An event whose number is not the current one is stale and
/// changes nothing; a stale `opened` closes its socket so none is left open.
///
/// A connect that never answers cannot wedge the machine: entering `connecting` starts a timeout
/// that moves it to `backingOff` and closes the attempt, and the late result, if any, is stale.
///
/// `lastSeq` is the highest `seq` seen from the server. It survives drops, so a reconnect sends
/// `Resume(lastSeq:)`. Before any sequenced message arrives there is nothing to resume, and the
/// first connection sends no `Resume`. `failures` counts consecutive failed attempts and sets the
/// back-off delay; it resets when a connection opens.
public enum WebSocketMachine: Machine {
  public struct State: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
      case idle
      case connecting(failures: Int)
      case connected
      case backingOff(failures: Int)
    }

    public var phase: Phase
    public var lastSeq: Int?
    /// The number of the most recent attempt. Zero before the first.
    public var attempt: Int

    public init(phase: Phase, lastSeq: Int?, attempt: Int) {
      self.phase = phase
      self.lastSeq = lastSeq
      self.attempt = attempt
    }

    public static let initial = State(phase: .idle, lastSeq: nil, attempt: 0)

    fileprivate func moved(to phase: Phase, attempt: Int? = nil, lastSeq: Int?? = nil) -> State {
      State(phase: phase, lastSeq: lastSeq ?? self.lastSeq, attempt: attempt ?? self.attempt)
    }
  }

  public enum Event: Equatable, Sendable {
    case connectRequested
    case disconnectRequested
    case sendRequested(ClientMessage)
    /// The socket of this attempt finished its handshake.
    case opened(attempt: Int)
    /// The attempt's socket failed or closed, or opening it failed.
    case dropped(attempt: Int)
    case received(attempt: Int, ServerMessage)
    case connectTimedOut(attempt: Int)
    case retryElapsed(attempt: Int)

    /// The attempt this event reports on, or `nil` for a request from the caller.
    var attempt: Int? {
      switch self {
      case .connectRequested, .disconnectRequested, .sendRequested:
        return nil
      case .opened(let attempt), .dropped(let attempt), .received(let attempt, _),
        .connectTimedOut(let attempt), .retryElapsed(let attempt):
        return attempt
      }
    }
  }

  public enum Output: Equatable, Sendable {
    case open(attempt: Int)
    /// Closes this attempt's socket if it has one. Harmless if it has none.
    case close(attempt: Int)
    case send(ClientMessage, attempt: Int)
    case startConnectTimeout(attempt: Int)
    case scheduleRetry(afterFailures: Int, attempt: Int)
    case deliver(ServerMessage)
  }

  public static let connectTimeout = Duration.seconds(10)

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    if let attempt = event.attempt, attempt != state.attempt {
      if case .opened = event {
        return (state, [.close(attempt: attempt)])
      }
      return (state, [])
    }

    let id = state.attempt
    switch (state.phase, event) {
    case (.idle, .connectRequested):
      return (state.moved(to: .connecting(failures: 0), attempt: id + 1), opening(id + 1))

    case (.connecting, .opened):
      let resume = state.lastSeq.map { [Output.send(.resume(lastSeq: $0), attempt: id)] } ?? []
      return (state.moved(to: .connected), resume)

    case (.connecting(let failures), .dropped),
      (.connecting(let failures), .connectTimedOut):
      return (
        state.moved(to: .backingOff(failures: failures + 1)),
        [.close(attempt: id), .scheduleRetry(afterFailures: failures + 1, attempt: id)]
      )

    case (.connected, .dropped):
      return (
        state.moved(to: .backingOff(failures: 1)),
        [.close(attempt: id), .scheduleRetry(afterFailures: 1, attempt: id)]
      )

    case (.backingOff(let failures), .retryElapsed):
      return (state.moved(to: .connecting(failures: failures), attempt: id + 1), opening(id + 1))

    case (.connecting, .disconnectRequested),
      (.connected, .disconnectRequested),
      (.backingOff, .disconnectRequested):
      return (state.moved(to: .idle), [.close(attempt: id)])

    case (.connected, .received(_, let message)):
      return (
        state.moved(to: .connected, lastSeq: .some(advance(state.lastSeq, past: message))),
        [.deliver(message)]
      )

    case (.connected, .sendRequested(let message)):
      return (state, [.send(message, attempt: id)])

    // A socket that finished opening after the caller stopped waiting for it.
    case (.idle, .opened),
      (.backingOff, .opened):
      return (state, [.close(attempt: id)])

    case (.idle, .disconnectRequested),
      (.idle, .dropped),
      (.idle, .received),
      (.idle, .retryElapsed),
      (.idle, .connectTimedOut),
      (.idle, .sendRequested),
      (.connecting, .connectRequested),
      (.connecting, .received),
      (.connecting, .retryElapsed),
      (.connecting, .sendRequested),
      (.connected, .connectRequested),
      (.connected, .opened),
      (.connected, .retryElapsed),
      (.connected, .connectTimedOut),
      (.backingOff, .connectRequested),
      (.backingOff, .dropped),
      (.backingOff, .received),
      (.backingOff, .connectTimedOut),
      (.backingOff, .sendRequested):
      return (state, [])
    }
  }

  /// Doubles from one second up to thirty-two.
  public static func retryDelay(afterFailures failures: Int) -> Duration {
    let exponent = min(max(failures - 1, 0), 5)
    return .seconds(1 << exponent)
  }

  private static func opening(_ attempt: Int) -> [Output] {
    [.open(attempt: attempt), .startConnectTimeout(attempt: attempt)]
  }

  private static func advance(_ lastSeq: Int?, past message: ServerMessage) -> Int? {
    switch message {
    case .stroke(let seq, _), .noteReceived(let seq, _):
      return max(lastSeq ?? seq, seq)
    case .presence:
      return lastSeq
    }
  }
}
