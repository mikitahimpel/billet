import Wire

public enum InkDecoder {
  /// Expands compact strokes back into unit-square strokes. `resolution` must match the encoder's.
  public static func decode(
    _ compact: CompactStrokes, resolution: Int = InkEncoder.Parameters().resolution
  ) throws(InkError) -> [Stroke] {
    guard resolution > 0 else { throw InkError.invalidParameters }
    let scale = Double(resolution)
    var strokes: [Stroke] = []
    for (index, stroke) in compact.strokes.enumerated() {
      guard stroke.points.count.isMultiple(of: 2) else {
        throw InkError.oddPointCount(strokeIndex: index)
      }
      let points = stride(from: 0, to: stroke.points.count, by: 2).map {
        Point(x: Double(stroke.points[$0]) / scale, y: Double(stroke.points[$0 + 1]) / scale)
      }
      strokes.append(
        Stroke(color: stroke.color, width: Double(stroke.width) / scale, points: points))
    }
    return strokes
  }
}
