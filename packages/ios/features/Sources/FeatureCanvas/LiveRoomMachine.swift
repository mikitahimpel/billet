import BilletKit
import Wire

/// What the partner is doing in the room. Live strokes are never stored, so a socket drop forgets
/// them; each phone sends its finished strokes again when the link comes back or the partner
/// starts drawing. A finished stroke keeps its live id, so a stroke sent twice replaces itself and
/// `strokesKept` takes away what the sender undid, erased or cleared. The server replays notes
/// after the last `seq` the client holds, and `lastNoteSeq` drops any it sends twice.
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
    /// The partner's finished strokes since their drawing began, oldest first, by live id; `nil`
    /// for a whole `stroke` frame, which has none.
    public var partnerStrokes: [PartnerStroke]
    /// The partner's strokes still being drawn, by their live id.
    public var openStrokes: [Int: Stroke]
    public var lastNoteSeq: Int?
    /// This phone's finished strokes, as its canvas last said.
    public var mine: [LiveStroke]
    /// Which of ``mine`` the partner has been sent on this link while this phone draws.
    public var shown: Set<Int>

    public init(
      isOnline: Bool = false, partner: PartnerPresence? = nil, strokes: [Stroke] = [],
      openStrokes: [Int: Stroke] = [:], lastNoteSeq: Int? = nil, mine: [LiveStroke] = [],
      shown: Set<Int> = []
    ) {
      self.isOnline = isOnline
      self.partner = partner
      self.partnerStrokes = strokes.map { PartnerStroke(id: nil, stroke: $0) }
      self.openStrokes = openStrokes
      self.lastNoteSeq = lastNoteSeq
      self.mine = mine
      self.shown = shown
    }

    /// The partner's finished strokes, oldest first.
    public var strokes: [Stroke] { partnerStrokes.map(\.stroke) }

    mutating func forgetDrawing() {
      partnerStrokes = []
      openStrokes = [:]
    }

    /// Replaces the partner's stroke with the same id in place, else adds it last.
    mutating func put(_ stroke: Stroke, id: Int?) {
      if let id, let at = partnerStrokes.firstIndex(where: { $0.id == id }) {
        partnerStrokes[at] = PartnerStroke(id: id, stroke: stroke)
        return
      }
      partnerStrokes.append(PartnerStroke(id: id, stroke: stroke))
      if partnerStrokes.count > LiveRoomMachine.strokeLimit {
        partnerStrokes.removeFirst(partnerStrokes.count - LiveRoomMachine.strokeLimit)
      }
    }
  }

  public struct PartnerStroke: Equatable, Sendable {
    public let id: Int?
    public let stroke: Stroke
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
    /// This phone's finished strokes after any change: a stroke ended, an undo, the eraser, a
    /// clear.
    case canvasChanged([LiveStroke])
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
      guard online else {
        next.partner = nil
        next.forgetDrawing()
        next.shown = []
        return (next, [])
      }
      // The room told the partner this phone left, and they let its drawing go.
      return state.isOnline ? (next, []) : resync(next)

    case .received(.stroke(_, let stroke)):
      guard state.isOnline else { return (state, []) }
      next.partner = .drawing
      next.put(stroke, id: nil)
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
      if !open.points.isEmpty { next.put(open, id: id) }
      return (next, [])

    case .received(.strokeDropped(let id)):
      next.openStrokes[id] = nil
      return (next, [])

    case .received(.clear):
      guard state.isOnline else { return (state, []) }
      next.forgetDrawing()
      return (next, [.partnerCleared])

    case .received(.strokesShown(let strokes)):
      guard state.isOnline else { return (state, []) }
      next.partner = .drawing
      for shown in strokes {
        next.openStrokes[shown.id] = nil
        next.put(shown.stroke, id: shown.id)
      }
      return (next, [])

    case .received(.strokesKept(let ids)):
      guard state.isOnline else { return (state, []) }
      let kept = Set(ids)
      next.partnerStrokes.removeAll { stroke in stroke.id.map { !kept.contains($0) } ?? false }
      return (next, [])

    case .received(.presence(let presence)):
      guard state.isOnline else { return (state, []) }
      next.partner = presence
      // A drawing the partner left without sending is gone.
      if presence != .drawing { next.forgetDrawing() }
      // A partner who opens the canvas, late or after a drop, holds none of this phone's strokes.
      if presence == .drawing, state.partner != .drawing { return resync(next) }
      return (next, [])

    // The canvas has nothing to do with the cat's journal, the Inbox or the moods.
    case .received(.catEntryAdded), .received(.catSaved), .received(.activityUnread),
      .received(.reactionChanged), .received(.shopChanged), .received(.listsChanged),
      .received(.moodChanged), .received(.matchFound), .received(.guessProgress),
      .received(.guessRevealed), .received(.riddleChanged), .received(.streakChanged):
      return (state, [])

    case .received(.noteReceived(let seq, let note)):
      if let last = state.lastNoteSeq, seq <= last { return (state, []) }
      next.lastNoteSeq = seq
      next.forgetDrawing()
      return (next, [.noteArrived(seq: seq, note)])

    case .presenceChanged(let presence):
      // The partner lets go of a drawing whose author stops drawing.
      next.mine = []
      next.shown = []
      return (next, state.isOnline ? [.send(.presence(presence))] : [])

    case .strokeDrawn(let stroke):
      return (state, state.isOnline ? [.send(.stroke(stroke))] : [])

    case .liveFrame(let message):
      guard state.isOnline else { return (state, []) }
      if case .strokeEnd(let id) = message { next.shown.insert(id) }
      return (next, [.send(message)])

    case .canvasChanged(let strokes):
      next.mine = strokes
      guard state.isOnline else { return (next, []) }
      let ids = Set(strokes.map(\.id))
      let missing = strokes.filter { !state.shown.contains($0.id) }
      next.shown = ids
      let removed = !state.shown.isSubset(of: ids)
      return (next, shown(missing) + (removed ? [kept(strokes)] : []))
    }
  }

  /// Sends every stroke of this phone's again, and which they are.
  private static func resync(_ state: State) -> (State, [Output]) {
    guard !state.mine.isEmpty else { return (state, []) }
    var next = state
    next.shown = Set(state.mine.map(\.id))
    return (next, shown(state.mine) + [kept(state.mine)])
  }

  /// Packs the strokes into frames of at most ``LiveStroke/maxPerFrame`` strokes and
  /// ``LiveStroke/maxPoints`` points, which keeps a frame under the room's 64 KB.
  private static func shown(_ strokes: [LiveStroke]) -> [Output] {
    var frames: [[LiveStroke]] = []
    var points = 0
    for stroke in strokes.map(\.thinned) {
      let count = stroke.stroke.points.count
      if let last = frames.last, last.count < LiveStroke.maxPerFrame,
        points + count <= LiveStroke.maxPoints
      {
        frames[frames.count - 1].append(stroke)
        points += count
      } else {
        frames.append([stroke])
        points = count
      }
    }
    return frames.map { .send(.strokesShown($0)) }
  }

  private static func kept(_ strokes: [LiveStroke]) -> Output {
    .send(.strokesKept(ids: strokes.suffix(LiveStroke.maxKept).map(\.id)))
  }
}
