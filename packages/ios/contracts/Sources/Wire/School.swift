/// A trick the app ships: lowercase words joined by hyphens, a letter first, at most 24
/// characters, such as `high-five`. The server only checks the shape.
public struct TrickId: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(rawValue: String) {
    guard rawValue.utf8.count <= 24, StoryId.isValid(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let id = TrickId(rawValue: value) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "TrickId: lowercase words joined by hyphens, at most 24 characters"
        ))
    }
    self = id
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A trick the pair's cat knows. `stars` is 1 to 3; `by` taught the first star; `at` is epoch
/// milliseconds of the latest.
public struct SchoolTrickEntry: Codable, Hashable, Sendable {
  public static let maxStars = 3

  public let trick: TrickId
  public let stars: Int
  public let by: UserId
  public let at: Int

  public init(trick: TrickId, stars: Int, by: UserId, at: Int) {
    self.trick = trick
    self.stars = stars
    self.by = by
    self.at = at
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    trick = try container.decode(TrickId.self, forKey: .trick)
    stars = try container.decode(Int.self, forKey: .stars)
    by = try container.decode(UserId.self, forKey: .by)
    at = try container.decode(Int.self, forKey: .at)
    guard (1...Self.maxStars).contains(stars) else {
      throw DecodingError.dataCorruptedError(
        forKey: .stars, in: container, debugDescription: "stars: 1 to \(Self.maxStars)")
    }
  }
}

/// One trick asked for in a routine, and whether the cat did it.
public struct RoutineStep: Codable, Hashable, Sendable {
  public let trick: TrickId
  public let landed: Bool

  public init(trick: TrickId, landed: Bool) {
    self.trick = trick
    self.landed = landed
  }
}

/// One take of a routine as it went: 3 to 5 steps. `at` is epoch milliseconds.
public struct Routine: Codable, Hashable, Sendable {
  public static let steps = 3...5

  public let steps: [RoutineStep]
  public let at: Int

  public init(steps: [RoutineStep], at: Int) {
    self.steps = steps
    self.at = at
  }
}

/// What the pair's cat knows, and the last routine each of the two sent.
public struct SchoolResponse: Codable, Hashable, Sendable {
  public let tricks: [SchoolTrickEntry]
  public let mine: Routine?
  public let partner: Routine?

  public init(tricks: [SchoolTrickEntry], mine: Routine? = nil, partner: Routine? = nil) {
    self.tricks = tricks
    self.mine = mine
    self.partner = partner
  }
}

/// A lesson passed. `stars` is the star it earns, one more than the trick has; a star already
/// held changes nothing, and a skipped one is refused.
public struct LessonRequest: Codable, Hashable, Sendable {
  public let trick: TrickId
  public let stars: Int

  public init(trick: TrickId, stars: Int) {
    self.trick = trick
    self.stars = stars
  }
}

/// Replaces this user's last routine. Every trick in it is one the cat knows.
public struct RoutineRequest: Codable, Hashable, Sendable {
  public let steps: [RoutineStep]

  public init(steps: [RoutineStep]) {
    self.steps = steps
  }
}
