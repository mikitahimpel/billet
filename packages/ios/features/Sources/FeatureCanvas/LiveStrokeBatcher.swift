import Wire

/// Turns one finger's stroke into the frames the room streams: a begin, then the points in
/// batches every ``interval`` (or as soon as a batch is full), then an end.
///
/// Pure: the caller passes the time, in seconds, with each event.
public struct LiveStrokeBatcher: Sendable {
  /// How long points wait before they are sent, so the partner sees them within a frame or two.
  public static let interval = 0.04

  private var id: Int?
  private var pending: [Point] = []
  private var lastFlush = 0.0
  private var nextID = 0

  public init() {}

  /// A new stroke starts. Ends any stroke still open first.
  public mutating func begin(color: String, width: Double, at point: Point, time: Double)
    -> [ClientMessage]
  {
    var frames = end()
    let started = nextID
    nextID = nextID == Int(Int32.max) ? 0 : nextID + 1
    id = started
    pending = [point]
    lastFlush = time
    frames.append(.strokeBegin(LiveStrokeStart(id: started, color: color, width: width)))
    return frames
  }

  /// The finger moved. Returns a points frame once the batch is due or full.
  public mutating func add(_ point: Point, time: Double) -> [ClientMessage] {
    guard id != nil else { return [] }
    pending.append(point)
    if pending.count >= LiveStrokeStart.maxPoints || time - lastFlush >= Self.interval {
      lastFlush = time
      return flush()
    }
    return []
  }

  /// Sends whatever is waiting, if it has waited long enough. Call from a ticking clock so the
  /// last points of a slow finger still go out.
  public mutating func tick(time: Double) -> [ClientMessage] {
    guard id != nil, !pending.isEmpty, time - lastFlush >= Self.interval else { return [] }
    lastFlush = time
    return flush()
  }

  /// The finger lifted: the last points, then the end.
  public mutating func end() -> [ClientMessage] {
    guard let open = id else { return [] }
    let frames = flush() + [.strokeEnd(id: open)]
    id = nil
    return frames
  }

  private mutating func flush() -> [ClientMessage] {
    guard let open = id, !pending.isEmpty else { return [] }
    let batch = pending
    pending = []
    let size = LiveStrokeStart.maxPoints
    return stride(from: 0, to: batch.count, by: size).map { start in
      .strokePoints(id: open, points: Array(batch[start..<min(start + size, batch.count)]))
    }
  }
}
