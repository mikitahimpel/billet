/// The day a wish is for, as the owner's phone named it: a title of 1 to 60 characters and the day
/// in epoch milliseconds. Each phone keeps its own calendar, so the wish carries both.
public struct GiftOccasion: Codable, Hashable, Sendable {
  public let title: String
  public let date: Int

  public init(title: String, date: Int) {
    self.title = title
    self.date = date
  }
}

/// Wire form of the contracts `GiftWish`: one partner's wish, as both partners see it. Who plans
/// to gift it is never here; `giftedBy` appears only once it arrived. Times are epoch milliseconds.
public struct GiftWish: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let owner: UserId
  public let title: String
  public let link: String
  public let price: String
  public let note: String
  public let mostWanted: Bool
  public let occasion: GiftOccasion?
  public let addedAt: Int
  public let receivedAt: Int?
  public let giftedBy: UserId?

  public init(
    id: IdempotencyKey, owner: UserId, title: String, link: String, price: String, note: String,
    mostWanted: Bool, occasion: GiftOccasion? = nil, addedAt: Int, receivedAt: Int? = nil,
    giftedBy: UserId? = nil
  ) {
    self.id = id
    self.owner = owner
    self.title = title
    self.link = link
    self.price = price
    self.note = note
    self.mostWanted = mostWanted
    self.occasion = occasion
    self.addedAt = addedAt
    self.receivedAt = receivedAt
    self.giftedBy = giftedBy
  }

  private enum CodingKeys: String, CodingKey {
    case id, owner, title, link, price, note, mostWanted, occasion, addedAt, receivedAt, giftedBy
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(IdempotencyKey.self, forKey: .id)
    owner = try container.decode(UserId.self, forKey: .owner)
    title = try container.decode(String.self, forKey: .title)
    link = try container.decode(String.self, forKey: .link)
    price = try container.decode(String.self, forKey: .price)
    note = try container.decode(String.self, forKey: .note)
    mostWanted = try container.decode(Bool.self, forKey: .mostWanted)
    occasion = try container.decodeOptionalKey(GiftOccasion.self, forKey: .occasion)
    addedAt = try container.decode(Int.self, forKey: .addedAt)
    receivedAt = try container.decodeOptionalKey(Int.self, forKey: .receivedAt)
    giftedBy = try container.decodeOptionalKey(UserId.self, forKey: .giftedBy)
  }
}

public enum GiftStage: String, Codable, Hashable, Sendable {
  case planning
  case bought
}

/// The caller's own secret promise to gift one of the partner's wishes.
public struct GiftPlan: Codable, Hashable, Sendable {
  public let wish: IdempotencyKey
  public let stage: GiftStage

  public init(wish: IdempotencyKey, stage: GiftStage) {
    self.wish = wish
    self.stage = stage
  }
}

/// What a partner likes, filled in by that partner. Each field is up to 200 characters.
public struct GiftLoves: Codable, Hashable, Sendable {
  public let sizes: String
  public let flowers: String
  public let coffee: String
  public let sweets: String
  public let allergies: String
  public let avoid: String

  public init(
    sizes: String, flowers: String, coffee: String, sweets: String, allergies: String,
    avoid: String
  ) {
    self.sizes = sizes
    self.flowers = flowers
    self.coffee = coffee
    self.sweets = sweets
    self.allergies = allergies
    self.avoid = avoid
  }
}

public struct PartnerLoves: Codable, Hashable, Sendable {
  public let user: UserId
  public let loves: GiftLoves

  public init(user: UserId, loves: GiftLoves) {
    self.user = user
    self.loves = loves
  }
}

/// The pair's gifts as the caller may see them: every wish, only the caller's own plans, and
/// `surprise` while the partner plans one of the caller's open wishes, without saying which.
public struct GiftsResponse: Codable, Hashable, Sendable {
  public let wishes: [GiftWish]
  public let plans: [GiftPlan]
  public let surprise: Bool
  public let loves: [PartnerLoves]

  public init(wishes: [GiftWish], plans: [GiftPlan], surprise: Bool, loves: [PartnerLoves]) {
    self.wishes = wishes
    self.plans = plans
    self.surprise = surprise
    self.loves = loves
  }
}

/// Makes the caller's wish, or changes one they made. The title is 1 to 200 characters, the link
/// up to 2048, the price up to 40 and the note up to 500.
public struct SaveGiftWishRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let title: String
  public let link: String
  public let price: String
  public let note: String
  public let mostWanted: Bool
  /// Nil clears it.
  public let occasion: GiftOccasion?

  public init(
    id: IdempotencyKey, title: String, link: String, price: String, note: String, mostWanted: Bool,
    occasion: GiftOccasion? = nil
  ) {
    self.id = id
    self.title = title
    self.link = link
    self.price = price
    self.note = note
    self.mostWanted = mostWanted
    self.occasion = occasion
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, link, price, note, mostWanted, occasion
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(IdempotencyKey.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    link = try container.decode(String.self, forKey: .link)
    price = try container.decode(String.self, forKey: .price)
    note = try container.decode(String.self, forKey: .note)
    mostWanted = try container.decode(Bool.self, forKey: .mostWanted)
    occasion = try container.decodeOptionalKey(GiftOccasion.self, forKey: .occasion)
  }
}

public struct DeleteGiftWishRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey

  public init(id: IdempotencyKey) {
    self.id = id
  }
}

/// Plans, moves on or, with no `stage`, lets go the caller's plan for one of the partner's wishes.
public struct SetGiftPlanRequest: Codable, Hashable, Sendable {
  public let wish: IdempotencyKey
  public let stage: GiftStage?

  public init(wish: IdempotencyKey, stage: GiftStage?) {
    self.wish = wish
    self.stage = stage
  }

  private enum CodingKeys: String, CodingKey {
    case wish, stage
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    wish = try container.decode(IdempotencyKey.self, forKey: .wish)
    stage = try container.decodeOptionalKey(GiftStage.self, forKey: .stage)
  }
}

public struct MarkGiftReceivedRequest: Codable, Hashable, Sendable {
  public let wish: IdempotencyKey
  public let received: Bool

  public init(wish: IdempotencyKey, received: Bool) {
    self.wish = wish
    self.received = received
  }
}

public struct SaveLovesRequest: Codable, Hashable, Sendable {
  public let loves: GiftLoves

  public init(loves: GiftLoves) {
    self.loves = loves
  }
}
