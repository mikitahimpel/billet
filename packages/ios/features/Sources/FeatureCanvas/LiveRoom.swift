import Foundation
import Observation
import Transport
import Wire

/// The room socket for the app while it is open: the partner's presence and live strokes in, this
/// phone's presence and strokes out. Runs ``LiveRoomMachine`` on the socket's messages.
///
/// The socket reconnects by itself and asks the server for the notes it has not seen, so a drop
/// loses live strokes (they are not stored) but no note and shows no note twice.
@MainActor
@Observable
public final class LiveRoom {
  public private(set) var state = LiveRoomMachine.State()

  @ObservationIgnored private var client: WebSocketClient?
  @ObservationIgnored private let onNote: (Int, Note) -> Void
  /// Called when the partner clears the shared canvas.
  @ObservationIgnored public var onClear: (() -> Void)?

  /// Spreads clumps of the partner's frames back out (#326); `held` are the messages waiting
  /// for their turn, in order, and `drain` draws them.
  @ObservationIgnored private var pacer = LivePacer()
  @ObservationIgnored private var held: [(at: Double, message: ServerMessage)] = []
  @ObservationIgnored private var drain: Task<Void, Never>?
  @ObservationIgnored private let now: @Sendable () -> Double
  @ObservationIgnored private let wait: @Sendable (Double) async -> Void

  /// - Parameters:
  ///   - makeDependencies: Builds the socket's services around the closure that receives each
  ///     server message.
  ///   - lastSeq: The last note `seq` this phone already holds.
  ///   - onNote: Called once for each note that arrives over the socket.
  ///   - now: A monotonic clock in seconds, and `wait` sleeps on it; both are for the pacer.
  public init(
    makeDependencies: (@escaping @Sendable (ServerMessage) async -> Void) -> WebSocketDependencies,
    lastSeq: Int?,
    onNote: @escaping (Int, Note) -> Void,
    now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
    wait: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
  ) {
    self.onNote = onNote
    self.now = now
    self.wait = wait
    state.lastNoteSeq = lastSeq
    let deliver: @Sendable (ServerMessage) async -> Void = { [weak self] message in
      await self?.receive(message)
    }
    client = WebSocketClient(dependencies: makeDependencies(deliver), lastSeq: lastSeq)
  }

  public func connect() { client?.connect() }

  public func disconnect() {
    client?.disconnect()
    syncLink()
  }

  /// Whether the socket is up now.
  public var isOnline: Bool {
    guard let phase = client?.state.phase else { return false }
    switch phase {
    case .connected: return true
    case .idle, .connecting, .backingOff: return false
    }
  }

  /// Brings the machine's view of the socket in line with the socket. Call when `isOnline`
  /// changes; receiving and sending do it too.
  public func syncLink() {
    let online = isOnline
    guard online != state.isOnline else { return }
    // Live frames held for pacing belong to the connection that just went; they are dropped
    // with it, as live strokes are.
    if !online {
      held.removeAll()
      pacer.reset()
    }
    apply(.linkChanged(online: online))
  }

  public func setDrawing(_ drawing: Bool) {
    syncLink()
    apply(.presenceChanged(drawing ? .drawing : .idle))
  }

  public func send(_ stroke: Stroke) {
    syncLink()
    apply(.strokeDrawn(stroke))
  }

  /// Sends a frame of this phone's live drawing; offline it is dropped, as live strokes are.
  public func sendLive(_ message: ClientMessage) {
    syncLink()
    apply(.liveFrame(message))
  }

  func receive(_ message: ServerMessage) {
    syncLink()
    let arrived = now()
    let at = pacer.draw(relayedAt: Self.relayedAt(of: message), arrived: arrived)
    if held.isEmpty, at <= arrived {
      apply(.received(message))
      return
    }
    held.append((at, message))
    if drain == nil { drain = Task { [weak self] in await self?.drawHeld() } }
  }

  /// Draws the held messages, each at its time.
  private func drawHeld() async {
    while let next = held.first {
      let remaining = next.at - now()
      if remaining > 0 { await wait(remaining) }
      // The link may have dropped meanwhile, which empties `held`.
      guard let first = held.first, first.at == next.at else { continue }
      held.removeFirst()
      apply(.received(first.message))
    }
    drain = nil
  }

  private static func relayedAt(of message: ServerMessage) -> Int? {
    if case .strokePoints(_, _, let relayedAt) = message { return relayedAt }
    return nil
  }

  private func apply(_ event: LiveRoomMachine.Event) {
    let (next, outputs) = LiveRoomMachine.transition(state, event)
    state = next
    for output in outputs {
      switch output {
      case .send(let message): client?.send(message)
      case .noteArrived(let seq, let note): onNote(seq, note)
      case .partnerCleared: onClear?()
      }
    }
  }
}

extension LiveRoom {
  /// The room over the real socket at `baseURL`, signed with the token `token` returns.
  public static func live(
    baseURL: URL,
    token: @escaping @Sendable () async -> String?,
    lastSeq: Int?,
    onNote: @escaping (Int, Note) -> Void
  ) -> LiveRoom {
    LiveRoom(
      makeDependencies: { deliver in
        WebSocketDependencies(
          open: { () async throws(TransportError) -> WebSocketConnection in
            guard let token = await token() else { throw .api(.unauthorized) }
            guard let request = URLRequest.socket(baseURL: baseURL, token: token) else {
              throw .network("invalid socket URL")
            }
            return try await WebSocketConnection.urlSession(request, session: .shared)
          },
          sleep: { try? await Task.sleep(for: $0) },
          deliver: deliver)
      },
      lastSeq: lastSeq, onNote: onNote)
  }
}
