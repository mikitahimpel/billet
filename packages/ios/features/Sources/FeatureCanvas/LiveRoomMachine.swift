import BilletKit
import Wire

/// What the partner is doing in the room. Live strokes are never stored, so a socket drop forgets
/// them. The server replays notes after the last `seq` the client holds, and `lastNoteSeq` drops
/// any it sends twice.
public enum LiveRoomMachine: Machine {
  /// More strokes than this in one live drawing are dropped from the front, so a stuck sender
  /// cannot grow the screen without bound.
  public static let strokeLimit = 500
  /// Points kept in one open live stroke; later ones are dropped until it ends.
  public static let openPointLimit = 4_000

  public struct State: Equatable, Sendable {
    public var isOnline: Bool
    /// `nil` until the server says, and again after a drop.
    public var partner: PartnerPresence?
    /// The partner's finished strokes since their drawing began, oldest first.
    public var strokes: [Stroke]
    /// The partner's strokes still being drawn, by their live id.
    public var openStrokes: [Int: Stroke]
    public var lastNoteSeq: Int?

    public init(
      isOnline: Bool = false, partner: PartnerPresence? = nil, strokes: [Stroke] = [],
      openStrokes: [Int: Stroke] = [:], lastNoteSeq: Int? = nil
    ) {
      self.isOnline = isOnline
      self.partner = partner
      self.strokes = strokes
      self.openStrokes = openStrokes
      self.lastNoteSeq = lastNoteSeq
    }

    mutating func forgetDrawing() {
      strokes = []
      openStrokes = [:]
    }

    mutating func append(_ stroke: Stroke) {
      strokes.append(stroke)
      if strokes.count > LiveRoomMachine.strokeLimit {
        strokes.removeFirst(strokes.count - LiveRoomMachine.strokeLimit)
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case linkChanged(online: Bool)
    case received(ServerMessage)
    /// This phone started or stopped drawing.
    case presenceChanged(PresenceState)
    /// This phone finished a stroke.
    case strokeDrawn(Stroke)
    /// A frame of this phone's live drawing: a stroke's begin, points or end, or a clear.
    case liveFrame(ClientMessage)
  }

  public enum Output: Equatable, Sendable {
    case send(ClientMessage)
    /// A note the partner sent, new to this client.
    case noteArrived(seq: Int, Note)
    /// The partner wiped the shared canvas, so this phone's strokes go too.
    case partnerCleared
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .linkChanged(let online):
      next.isOnline = online
      if !online {
        next.partner = nil
        next.forgetDrawing()
      }
      return (next, [])

    case .received(.stroke(_, let stroke)):
      guard state.isOnline else { return (state, []) }
      next.partner = .drawing
      next.append(stroke)
      return (next, [])

    case .received(.strokeBegin(let start)):
      guard state.isOnline else { return (state, []) }
      next.partner = .drawing
      next.openStrokes[start.id] = Stroke(color: start.color, width: start.width, points: [])
      return (next, [])

    case .received(.strokePoints(let id, let points, _)):
      guard state.isOnline, let open = state.openStrokes[id] else { return (state, []) }
      let room = max(openPointLimit - open.points.count, 0)
      next.openStrokes[id] = Stroke(
        color: open.color, width: open.width, points: open.points + points.prefix(room))
      return (next, [])

    case .received(.strokeEnd(let id)):
      guard state.isOnline, let open = next.openStrokes.removeValue(forKey: id) else {
        return (state, [])
      }
      if !open.points.isEmpty { next.append(open) }
      return (next, [])

    case .received(.strokeDropped(let id)):
      next.openStrokes[id] = nil
      return (next, [])

    case .received(.clear):
      guard state.isOnline else { return (state, []) }
      next.forgetDrawing()
      return (next, [.partnerCleared])

    case .received(.presence(let presence)):
      guard state.isOnline else { return (state, []) }
      next.partner = presence
      // A drawing the partner left without sending is gone.
      if presence != .drawing { next.forgetDrawing() }
      return (next, [])

    // The canvas has nothing to do with the cat's journal, the Inbox or the moods.
    case .received(.catEntryAdded), .received(.catSaved), .received(.activityUnread),
      .received(.reactionChanged), .received(.shopChanged), .received(.listsChanged),
      .received(.moodChanged), .received(.matchFound), .received(.guessProgress),
      .received(.guessRevealed), .received(.riddleChanged):
      return (state, [])

    case .received(.noteReceived(let seq, let note)):
      if let last = state.lastNoteSeq, seq <= last { return (state, []) }
      next.lastNoteSeq = seq
      next.forgetDrawing()
      return (next, [.noteArrived(seq: seq, note)])

    case .presenceChanged(let presence):
      return (state, state.isOnline ? [.send(.presence(presence))] : [])

    case .strokeDrawn(let stroke):
      return (state, state.isOnline ? [.send(.stroke(stroke))] : [])

    case .liveFrame(let message):
      return (state, state.isOnline ? [.send(message)] : [])
    }
  }
}
