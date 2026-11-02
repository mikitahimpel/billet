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

  /// - Parameters:
  ///   - makeDependencies: Builds the socket's services around the closure that receives each
  ///     server message.
  ///   - lastSeq: The last note `seq` this phone already holds.
  ///   - onNote: Called once for each note that arrives over the socket.
  public init(
    makeDependencies: (@escaping @Sendable (ServerMessage) async -> Void) -> WebSocketDependencies,
    lastSeq: Int?,
    onNote: @escaping (Int, Note) -> Void
  ) {
    self.onNote = onNote
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
    if online != state.isOnline { apply(.linkChanged(online: online)) }
  }

  public func setDrawing(_ drawing: Bool) {
    syncLink()
    apply(.presenceChanged(drawing ? .drawing : .idle))
  }

  public func send(_ stroke: Stroke) {
    syncLink()
    apply(.strokeDrawn(stroke))
  }

  func receive(_ message: ServerMessage) {
    syncLink()
    apply(.received(message))
  }

  private func apply(_ event: LiveRoomMachine.Event) {
    let (next, outputs) = LiveRoomMachine.transition(state, event)
    state = next
    for output in outputs {
      switch output {
      case .send(let message): client?.send(message)
      case .noteArrived(let seq, let note): onNote(seq, note)
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
