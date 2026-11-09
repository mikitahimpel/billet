/// The app owns the face and words; the wire carries only the id.
public enum CheckInMood: String, Codable, Hashable, Sendable, CaseIterable {
  case happy
  case sleepy
  case missing
  case busy
}

/// The room keeps one per member; a new one replaces it. `note` is trimmed, never empty, at most
/// 80 UTF-16 code units.
public struct PartnerCheckIn: Codable, Hashable, Sendable {
  public let user: UserId
  public let mood: CheckInMood
  public let note: String?
  /// Epoch milliseconds, by the room's clock.
  public let at: Int

  public init(user: UserId, mood: CheckInMood, note: String? = nil, at: Int) {
    self.user = user
    self.mood = mood
    self.note = note
    self.at = at
  }

  private enum CodingKeys: String, CodingKey {
    case user, mood, note, at
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    user = try container.decode(UserId.self, forKey: .user)
    mood = try container.decode(CheckInMood.self, forKey: .mood)
    note = try container.decodeOptionalKey(String.self, forKey: .note)
    at = try container.decode(Int.self, forKey: .at)
  }
}

/// The room trims `note` and drops it when blank; over 80 UTF-16 code units is `invalidRequest`.
public struct SetMoodRequest: Codable, Hashable, Sendable {
  public let mood: CheckInMood
  public let note: String?

  public init(mood: CheckInMood, note: String? = nil) {
    self.mood = mood
    self.note = note
  }

  private enum CodingKeys: String, CodingKey {
    case mood, note
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mood = try container.decode(CheckInMood.self, forKey: .mood)
    note = try container.decodeOptionalKey(String.self, forKey: .note)
  }
}
