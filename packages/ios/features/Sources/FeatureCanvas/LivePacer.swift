/// Decides when to draw each of the partner's live frames (#326).
///
/// The relay sometimes delivers several frames at once after a pause. Drawn as they arrive, the
/// stroke stalls and then jumps. A clump is instead replayed at the pace the room relayed it
/// (`StrokePoints.relayedAt`), a little faster than real time so the lag it adds drains away.
/// A steady stream passes straight through. No frame is ever held more than ``maxLag`` past its
/// arrival.
///
/// Frames keep their order: one without `relayedAt` (a begin, an end, a clear, or any frame
/// from an older room) waits for the frames before it.
public struct LivePacer: Equatable, Sendable {
  /// The most a frame is held past its arrival, in seconds.
  public static let maxLag = 0.2
  /// How much faster than real time a clump is replayed.
  public static let catchUp = 1.5

  /// The frame the current pace is measured from: its `relayedAt` and when it was drawn.
  private var anchor: (relayed: Int, drawn: Double)?
  private var lastDrawn = -Double.infinity

  public init() {}

  /// When to draw a frame that arrived at `now` (seconds on a monotonic clock), never earlier
  /// than the frame before it.
  public mutating func draw(relayedAt: Int?, arrived now: Double) -> Double {
    var at = now
    if let relayedAt {
      if let anchor {
        let paced = anchor.drawn + Double(relayedAt - anchor.relayed) / 1000 / Self.catchUp
        at = min(max(now, paced), now + Self.maxLag)
      }
      // A frame drawn as it arrived, or held to the limit, starts the pace afresh.
      if anchor == nil || at == now || at == now + Self.maxLag { anchor = (relayedAt, at) }
    }
    at = max(at, lastDrawn)
    lastDrawn = at
    return at
  }

  /// Forgets the pace, when the partner stops drawing or the socket drops.
  public mutating func reset() {
    anchor = nil
    lastDrawn = -Double.infinity
  }

  public static func == (lhs: LivePacer, rhs: LivePacer) -> Bool {
    lhs.anchor?.relayed == rhs.anchor?.relayed && lhs.anchor?.drawn == rhs.anchor?.drawn
      && lhs.lastDrawn == rhs.lastDrawn
  }
}
