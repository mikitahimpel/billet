/// Which of the pair's two phones is which, the same on both with no server: the lower account id is `first`.
public enum Side: Int, Equatable, Sendable {
  case first = 0
  case second = 1

  public init(viewer: String, partner: String) {
    self = viewer < partner ? .first : .second
  }

  public var other: Side { self == .first ? .second : .first }
}

/// Every beat has two halves and each partner sees one. The side flips with the beat's place in the episode, so
/// neither partner always holds the paw prints and the other always the letter.
public enum ClueSplit {
  public static func halfIndex(of side: Side, beat: Int) -> Int {
    (side.rawValue + beat) % 2
  }

  /// The half this side's phone shows for the beat at `beat`.
  public static func half(of beat: Episode.Beat, at index: Int, side: Side) -> Episode.Half {
    beat.halves[halfIndex(of: side, beat: index)]
  }
}
