/// The fixed set of house drawings. Each adds one thing to the one before it, and the set does not
/// grow with the streak.
public enum HouseStage: Int, CaseIterable, Comparable, Sendable {
  /// 0–6 days: the house itself, lit.
  case lit
  /// 7–20 days: a fence and two flowers.
  case garden
  /// 21–29 days: a two-trunked tree.
  case tree
  /// 30–59 days: a chimney whose two wisps cross into one heart, and the outline of the next room.
  case chimney
  /// 60 days and on: the new room, built.
  case newRoom

  /// The day each stage begins.
  public var firstDay: Int {
    switch self {
    case .lit: 0
    case .garden: 7
    case .tree: 21
    case .chimney: 30
    case .newRoom: 60
    }
  }

  public init(streak: Int) {
    self = Self.allCases.last { $0.firstDay <= streak } ?? .lit
  }

  public static func < (lhs: HouseStage, rhs: HouseStage) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
