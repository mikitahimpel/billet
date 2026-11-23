import Foundation

/// How well the cat knows one trick, and who first taught it.
public struct TrickSkill: Equatable, Hashable, Sendable {
  public static let maxStars = 3

  public let trick: SchoolTrick
  /// 1 to ``maxStars``.
  public let stars: Int
  public let teacher: String

  public init(trick: SchoolTrick, stars: Int, teacher: String) {
    self.trick = trick
    self.stars = min(max(stars, 1), Self.maxStars)
    self.teacher = teacher
  }

  /// How often the cat does the trick when asked: half the time at one star, always at three.
  public static func chance(stars: Int) -> Double {
    switch stars {
    case ...0: 0
    case 1: 0.5
    case 2: 0.75
    default: 1
    }
  }

  /// Whether the cat does it this time. `roll` is from 0 up to 1.
  public func lands(roll: Double) -> Bool { roll < Self.chance(stars: stars) }
}

/// One take of a routine as it went, flubs included, so it can be played again as it was.
public struct RoutineTake: Equatable, Hashable, Sendable {
  public static let length = 3...5

  public struct Step: Equatable, Hashable, Sendable {
    public let trick: SchoolTrick
    public let landed: Bool

    public init(trick: SchoolTrick, landed: Bool) {
      self.trick = trick
      self.landed = landed
    }
  }

  public let steps: [Step]
  public let at: Date

  public init(steps: [Step], at: Date) {
    self.steps = steps
    self.at = at
  }

  /// What the room plays, in order.
  public var moves: [SchoolMove] {
    steps.enumerated().map { index, step in
      step.landed ? .trick(step.trick) : .flub(SchoolFlub(turn: index))
    }
  }

  public var landed: Int { steps.count { $0.landed } }
}

/// What the pair's cat knows and the last routine each of the two sent.
public struct SchoolBook: Equatable, Sendable {
  public var skills: [SchoolTrick: TrickSkill]
  public var mine: RoutineTake?
  public var partner: RoutineTake?

  public init(
    skills: [SchoolTrick: TrickSkill] = [:], mine: RoutineTake? = nil, partner: RoutineTake? = nil
  ) {
    self.skills = skills
    self.mine = mine
    self.partner = partner
  }

  public func stars(of trick: SchoolTrick) -> Int { skills[trick]?.stars ?? 0 }

  /// The star the next lesson of `trick` earns, or nil when it has them all.
  public func nextStar(of trick: SchoolTrick) -> Int? {
    let stars = stars(of: trick)
    return stars < TrickSkill.maxStars ? stars + 1 : nil
  }

  /// The tricks a routine can hold, in the order the app lists them.
  public var known: [SchoolTrick] { SchoolTrick.allCases.filter { skills[$0] != nil } }

  public var canBuildRoutine: Bool { !known.isEmpty }
}
