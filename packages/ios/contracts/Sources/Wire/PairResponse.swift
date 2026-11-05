/// `GET /v1/pair`: the caller's pair and both members, the caller first. 404 while unpaired.
public struct PairResponse: Codable, Hashable, Sendable {
  public let pairId: PairId
  public let members: [UserId]

  public init(pairId: PairId, members: [UserId]) {
    self.pairId = pairId
    self.members = members
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pairId = try container.decode(PairId.self, forKey: .pairId)
    members = try container.decode([UserId].self, forKey: .members)
    guard members.count == 2, members[0] != members[1] else {
      throw DecodingError.dataCorruptedError(
        forKey: .members, in: container, debugDescription: "a pair has two different members")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case pairId
    case members
  }
}
