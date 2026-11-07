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
/// A server that accepts a connection and then drops it at once must not be retried every second
/// for ever. `failures` therefore survives an opening and is only cleared once the connection has
/// stayed up for ``stableAfter``, reported by the `stable` event.
///
/// `lastSeq` is the highest `seq` seen from the server. It survives drops, so a reconnect sends
/// `Resume(lastSeq:)`; the first connection resumes from zero. The `open` output carries it, and
/// the runner queues the `Resume` as soon as the socket is up, so it goes before anything the
/// caller sends. `lastSeq` cannot change while connecting, as messages only arrive once connected. `failures` counts consecutive failed attempts and sets the
/// back-off delay.
public enum WebSocketMachine: Machine {
  public struct State: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
      case idle
      case connecting(failures: Int)
      case connected(failures: Int)
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
    /// The attempt's connection has stayed up for ``WebSocketMachine/stableAfter``.
    case stable(attempt: Int)

    /// The attempt this event reports on, or `nil` for a request from the caller.
    var attempt: Int? {
      switch self {
      case .connectRequested, .disconnectRequested, .sendRequested:
        return nil
      case .opened(let attempt), .dropped(let attempt), .received(let attempt, _),
        .connectTimedOut(let attempt), .retryElapsed(let attempt), .stable(let attempt):
        return attempt
      }
    }
  }

  public enum Output: Equatable, Sendable {
    /// Opens the attempt's socket and sends `Resume(lastSeq: resumeFrom)` before anything else.
    case open(attempt: Int, resumeFrom: Int)
    /// Closes this attempt's socket if it has one. Harmless if it has none.
    case close(attempt: Int)
    case send(ClientMessage, attempt: Int)
    case startConnectTimeout(attempt: Int)
    /// Reports `stable` for this attempt after ``WebSocketMachine/stableAfter``, unless the attempt
    /// ends first.
    case startStabilityTimer(attempt: Int)
    case scheduleRetry(afterFailures: Int, attempt: Int)
    case deliver(ServerMessage)
  }

  public static let connectTimeout = Duration.seconds(10)
  /// How long a connection must stay up before the failures that led to it are forgotten.
  public static let stableAfter = Duration.seconds(30)

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
      return (state.moved(to: .connecting(failures: 0), attempt: id + 1), opening(id + 1, state))

    case (.connecting(let failures), .opened):
      return (state.moved(to: .connected(failures: failures)), [.startStabilityTimer(attempt: id)])

    case (.connected, .stable):
      return (state.moved(to: .connected(failures: 0)), [])

    case (.connecting(let failures), .dropped),
      (.connecting(let failures), .connectTimedOut):
      return (
        state.moved(to: .backingOff(failures: failures + 1)),
        [.close(attempt: id), .scheduleRetry(afterFailures: failures + 1, attempt: id)]
      )

    case (.connected(let failures), .dropped):
      return (
        state.moved(to: .backingOff(failures: failures + 1)),
        [.close(attempt: id), .scheduleRetry(afterFailures: failures + 1, attempt: id)]
      )

    case (.backingOff(let failures), .retryElapsed):
      return (
        state.moved(to: .connecting(failures: failures), attempt: id + 1), opening(id + 1, state)
      )

    case (.connecting, .disconnectRequested),
      (.connected, .disconnectRequested),
      (.backingOff, .disconnectRequested):
      return (state.moved(to: .idle), [.close(attempt: id)])

    case (.connected, .received(_, let message)):
      return (
        state.moved(to: state.phase, lastSeq: .some(advance(state.lastSeq, past: message))),
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
      (.idle, .stable),
      (.connecting, .stable),
      (.backingOff, .stable),
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

  /// The server sends no note to a socket that has not asked, so every connection resumes, from
  /// zero when nothing has been received.
  private static func opening(_ attempt: Int, _ state: State) -> [Output] {
    [
      .open(attempt: attempt, resumeFrom: state.lastSeq ?? 0),
      .startConnectTimeout(attempt: attempt),
    ]
  }

  private static func advance(_ lastSeq: Int?, past message: ServerMessage) -> Int? {
    switch message {
    case .noteReceived(let seq, _):
      return max(lastSeq ?? seq, seq)
    // A live stroke carries the room's latest note `seq`, which this client may not have received
    // yet, so counting it would let a reconnect skip notes.
    // Cat frames have their own journal `seq`, never a note's, and the Inbox count has none.
    case .stroke, .presence, .strokeBegin, .strokePoints, .strokeEnd, .strokeDropped, .clear,
      .catEntryAdded, .catSaved, .activityUnread, .reactionChanged, .shopChanged, .listsChanged,
      .moodChanged, .matchFound, .guessProgress, .guessRevealed, .riddleChanged:
      return lastSeq
    }
  }
}
