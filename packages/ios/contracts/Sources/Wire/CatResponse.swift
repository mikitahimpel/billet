/// `cat` is `nil` until adopted; `lastSeq` is the journal's last entry, 0 when empty.
public struct CatResponse: Codable, Hashable, Sendable {
  public let cat: CatProfile?
  public let temper: CatTemper
  public let needs: CatNeeds
  public let lastSeq: Int

  public init(cat: CatProfile?, temper: CatTemper, needs: CatNeeds, lastSeq: Int) {
    self.cat = cat
    self.temper = temper
    self.needs = needs
    self.lastSeq = lastSeq
  }

  private enum CodingKeys: String, CodingKey {
    case cat
    case temper
    case needs
    case lastSeq
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cat = try container.decodeOptionalKey(CatProfile.self, forKey: .cat)
    temper = try container.decode(CatTemper.self, forKey: .temper)
    needs = try container.decode(CatNeeds.self, forKey: .needs)
    lastSeq = try container.decode(Int.self, forKey: .lastSeq)
  }
}

/// The first save adopts the cat; later ones change its name, look and the pair's clock.
public struct SaveCatRequest: Codable, Hashable, Sendable {
  public let name: String
  public let look: CatLook
  public let utcOffsetSeconds: Int

  public init(name: String, look: CatLook, utcOffsetSeconds: Int) {
    self.name = name
    self.look = look
    self.utcOffsetSeconds = utcOffsetSeconds
  }
}

/// `id` is made once and repeated on every retry of the same event.
public struct RecordCatEventRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let event: CatEvent

  public init(id: IdempotencyKey, event: CatEvent) {
    self.id = id
    self.event = event
  }
}

/// The stored entry, or the first one under the same `id`.
public struct RecordCatEventResponse: Codable, Hashable, Sendable {
  public let entry: CatEntry
  public let temper: CatTemper
  public let needs: CatNeeds

  public init(entry: CatEntry, temper: CatTemper, needs: CatNeeds) {
    self.entry = entry
    self.temper = temper
    self.needs = needs
  }
}
