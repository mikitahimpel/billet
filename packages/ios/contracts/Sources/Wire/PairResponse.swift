/// A member's display name, as `PUT /v1/me` set it.
public struct MemberName: Codable, Hashable, Sendable {
  public let userId: UserId
  public let displayName: String

  public init(userId: UserId, displayName: String) {
    self.userId = userId
    self.displayName = displayName
  }
}

/// The caller first; 404 while unpaired. `moods` holds members who have checked in; a server
/// before moods sends none, and a check-in this build can't read is left out. `names`,
/// `togetherSince` (YYYY-MM-DD, once a partner set it) and `pairedAt` (epoch ms) are absent from
/// older servers.
public struct PairResponse: Codable, Hashable, Sendable {
  public let pairId: PairId
  public let members: [UserId]
  public let moods: [PartnerCheckIn]
  public let names: [MemberName]?
  public let togetherSince: String?
  public let pairedAt: Int?

  public init(
    pairId: PairId, members: [UserId], moods: [PartnerCheckIn] = [], names: [MemberName]? = nil,
    togetherSince: String? = nil, pairedAt: Int? = nil
  ) {
    self.pairId = pairId
    self.members = members
    self.moods = moods
    self.names = names
    self.togetherSince = togetherSince
    self.pairedAt = pairedAt
  }

  /// The member's name, if they set one.
  public func name(of user: UserId) -> String? {
    names?.first { $0.userId == user }?.displayName
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pairId = try container.decode(PairId.self, forKey: .pairId)
    members = try container.decode([UserId].self, forKey: .members)
    guard members.count == 2, members[0] != members[1] else {
      throw DecodingError.dataCorruptedError(
        forKey: .members, in: container, debugDescription: "a pair has two different members")
    }
    moods =
      container.contains(.moods)
      ? try container.decodeLossyArray(PartnerCheckIn.self, forKey: .moods) : []
    names =
      container.contains(.names)
      ? try container.decodeLossyArray(MemberName.self, forKey: .names) : nil
    togetherSince = try container.decodeOptionalKey(String.self, forKey: .togetherSince)
    pairedAt = try container.decodeOptionalKey(Int.self, forKey: .pairedAt)
  }

  private enum CodingKeys: String, CodingKey {
    case pairId
    case members
    case moods
    case names
    case togetherSince
    case pairedAt
  }
}
