import BilletKit
import Wire

/// What the partner is doing in the room, from the app's side of the socket.
///
/// Live strokes are never stored or replayed by the server, so they exist only while the socket
/// is up: a drop forgets them, and a reconnect starts the partner's drawing again from nothing.
/// Notes are the other way round. The server replays those after the last `seq` the client holds,
/// and `lastNoteSeq` drops any it sends twice.
public enum LiveRoomMachine: Machine {
  /// More strokes than this in one live drawing are dropped from the front, so a stuck sender
  /// cannot grow the screen without bound.
  public static let strokeLimit = 500

  public struct State: Equatable, Sendable {
    public var isOnline: Bool
    /// `nil` until the server says, and again after a drop.
    public var partner: PresenceState?
    /// The partner's strokes since their drawing began, oldest first.
    public var strokes: [Stroke]
    public var lastNoteSeq: Int?

    public init(
      isOnline: Bool = false, partner: PresenceState? = nil, strokes: [Stroke] = [],
      lastNoteSeq: Int? = nil
    ) {
      self.isOnline = isOnline
      self.partner = partner
      self.strokes = strokes
      self.lastNoteSeq = lastNoteSeq
    }
  }

  public enum Event: Equatable, Sendable {
    case linkChanged(online: Bool)
    case received(ServerMessage)
    /// This phone started or stopped drawing.
    case presenceChanged(PresenceState)
    /// This phone finished a stroke.
    case strokeDrawn(Stroke)
  }

  public enum Output: Equatable, Sendable {
    case send(ClientMessage)
    /// A note the partner sent, new to this client.
    case noteArrived(seq: Int, Note)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .linkChanged(let online):
      next.isOnline = online
      if !online {
        next.partner = nil
        next.strokes = []
      }
      return (next, [])

    case .received(.stroke(_, let stroke)):
      guard state.isOnline else { return (state, []) }
      next.partner = .drawing
      next.strokes.append(stroke)
      if next.strokes.count > strokeLimit {
        next.strokes.removeFirst(next.strokes.count - strokeLimit)
      }
      return (next, [])

    case .received(.presence(let presence)):
      guard state.isOnline else { return (state, []) }
      next.partner = presence
      // A drawing the partner left without sending is gone.
      if presence == .idle { next.strokes = [] }
      return (next, [])

    case .received(.noteReceived(let seq, let note)):
      if let last = state.lastNoteSeq, seq <= last { return (state, []) }
      next.lastNoteSeq = seq
      next.strokes = []
      return (next, [.noteArrived(seq: seq, note)])

    case .presenceChanged(let presence):
      return (state, state.isOnline ? [.send(.presence(presence))] : [])

    case .strokeDrawn(let stroke):
      return (state, state.isOnline ? [.send(.stroke(stroke))] : [])
    }
  }
}
