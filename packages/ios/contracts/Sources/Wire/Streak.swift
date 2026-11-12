/// A member did their part on `day`, their own local day, which isn't lit yet.
public struct StreakMark: Codable, Hashable, Sendable {
  public let user: UserId
  public let day: String

  public init(user: UserId, day: String) {
    self.user = user
    self.day = day
  }
}

/// `days` is the run up to `lastDay` and stays after a break, so a restore can bring it back.
/// Days are local, `YYYY-MM-DD`. `marks` are the days after `lastDay` only one partner did yet.
public struct PairStreak: Codable, Hashable, Sendable {
  public let days: Int
  public let best: Int
  public let lastDay: String?
  public let restoredOn: String?
  public let marks: [StreakMark]?

  public init(
    days: Int, best: Int, lastDay: String? = nil, restoredOn: String? = nil,
    marks: [StreakMark]? = nil
  ) {
    self.days = days
    self.best = best
    self.lastDay = lastDay
    self.restoredOn = restoredOn
    self.marks = marks
  }

  private enum CodingKeys: String, CodingKey {
    case days, best, lastDay, restoredOn, marks
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    days = try container.decode(Int.self, forKey: .days)
    best = try container.decode(Int.self, forKey: .best)
    lastDay = try container.decodeOptionalKey(String.self, forKey: .lastDay)
    restoredOn = try container.decodeOptionalKey(String.self, forKey: .restoredOn)
    marks = try container.decodeOptionalKey([StreakMark].self, forKey: .marks)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(days, forKey: .days)
    try container.encode(best, forKey: .best)
    try container.encodeIfPresent(lastDay, forKey: .lastDay)
    try container.encodeIfPresent(restoredOn, forKey: .restoredOn)
    try container.encodeIfPresent(marks, forKey: .marks)
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
