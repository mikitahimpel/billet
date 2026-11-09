/// `days` is the run up to `lastDay` and stays after a break, so a restore can bring it back.
/// Days are local, `YYYY-MM-DD`.
public struct PairStreak: Codable, Hashable, Sendable {
  public let days: Int
  public let best: Int
  public let lastDay: String?
  public let restoredOn: String?

  public init(days: Int, best: Int, lastDay: String? = nil, restoredOn: String? = nil) {
    self.days = days
    self.best = best
    self.lastDay = lastDay
    self.restoredOn = restoredOn
  }

  private enum CodingKeys: String, CodingKey {
    case days, best, lastDay, restoredOn
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    days = try container.decode(Int.self, forKey: .days)
    best = try container.decode(Int.self, forKey: .best)
    lastDay = try container.decodeOptionalKey(String.self, forKey: .lastDay)
    restoredOn = try container.decodeOptionalKey(String.self, forKey: .restoredOn)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(days, forKey: .days)
    try container.encode(best, forKey: .best)
    try container.encodeIfPresent(lastDay, forKey: .lastDay)
    try container.encodeIfPresent(restoredOn, forKey: .restoredOn)
  }
}

public struct StreakResponse: Codable, Hashable, Sendable {
  public let streak: PairStreak

  public init(streak: PairStreak) {
    self.streak = streak
  }
}

/// `at` is epoch milliseconds by the phone's clock; the room counts it at most a day back.
public struct RecordStreakDayRequest: Codable, Hashable, Sendable {
  public let at: Int
  public let utcOffsetSeconds: Int

  public init(at: Int, utcOffsetSeconds: Int) {
    self.at = at
    self.utcOffsetSeconds = utcOffsetSeconds
  }
}

public struct RestoreStreakRequest: Codable, Hashable, Sendable {
  public let utcOffsetSeconds: Int

  public init(utcOffsetSeconds: Int) {
    self.utcOffsetSeconds = utcOffsetSeconds
  }
}
