/// `GET /v1/pair`: the caller's pair and both members, the caller first. 404 while unpaired.
/// `moods` holds each member's latest check-in, for those who have checked in; a server before
/// moods sends none, and a check-in this build can't read is left out.
public struct PairResponse: Codable, Hashable, Sendable {
  public let pairId: PairId
  public let members: [UserId]
  public let moods: [PartnerCheckIn]

  public init(pairId: PairId, members: [UserId], moods: [PartnerCheckIn] = []) {
    self.pairId = pairId
    self.members = members
    self.moods = moods
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
  }

  private enum CodingKeys: String, CodingKey {
    case pairId
    case members
    case moods
  }
}
