/// A trick the cat can be taught. The raw value is the id the server keeps.
public enum SchoolTrick: String, CaseIterable, Codable, Hashable, Sendable {
  case spin
  case jump
  case highFive = "high-five"
  case bow

  public var title: String {
    switch self {
    case .spin: "Spin"
    case .jump: "Jump"
    case .highFive: "High five"
    case .bow: "Bow"
    }
  }
}

/// What the cat does instead of a trick it was asked for.
public enum SchoolFlub: String, CaseIterable, Codable, Hashable, Sendable {
  case yawn
  case groom
  case tilt
  case shake

  /// The same flub for the same count, so a take replays as it went.
  public init(turn: Int) {
    let all = Self.allCases
    self = all[((turn % all.count) + all.count) % all.count]
  }
}

/// One thing the room's cat is asked to do for the school.
public enum SchoolMove: Equatable, Hashable, Sendable {
  case trick(SchoolTrick)
  case flub(SchoolFlub)
}
