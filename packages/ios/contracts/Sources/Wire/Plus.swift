public enum PlusPlan: String, Codable, Hashable, Sendable, CaseIterable {
  case monthly
  case yearly
}

/// The pair's Plus as the caller sees it. `active`, `ending` and `grace` are the caller's own
/// subscription; `shared` is the partner's, with no plan, price or dates. `ended`: the pair had
/// Plus and has it no longer; parcels not opened yet still open. Dates are ISO 8601 UTC.
public enum PlusState: Codable, Hashable, Sendable {
  case none
  case active(plan: PlusPlan, renewsOn: String)
  /// Renewal is off; Plus runs until `until`.
  case ending(plan: PlusPlan, until: String)
  /// Apple could not take the payment and is retrying; parcels keep coming.
  case grace(plan: PlusPlan)
  case shared
  case ended

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case plan, renewsOn, until
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "None": self = .none
    case "Active":
      self = .active(
        plan: try container.decode(PlusPlan.self, forKey: .plan),
        renewsOn: try container.decode(String.self, forKey: .renewsOn))
    case "Ending":
      self = .ending(
        plan: try container.decode(PlusPlan.self, forKey: .plan),
        until: try container.decode(String.self, forKey: .until))
    case "Grace": self = .grace(plan: try container.decode(PlusPlan.self, forKey: .plan))
    case "Shared": self = .shared
    case "Ended": self = .ended
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .none: try container.encode("None", forKey: .tag)
    case .active(let plan, let renewsOn):
      try container.encode("Active", forKey: .tag)
      try container.encode(plan, forKey: .plan)
      try container.encode(renewsOn, forKey: .renewsOn)
    case .ending(let plan, let until):
      try container.encode("Ending", forKey: .tag)
      try container.encode(plan, forKey: .plan)
      try container.encode(until, forKey: .until)
    case .grace(let plan):
      try container.encode("Grace", forKey: .tag)
      try container.encode(plan, forKey: .plan)
    case .shared: try container.encode("Shared", forKey: .tag)
    case .ended: try container.encode("Ended", forKey: .tag)
    }
  }
}

/// What a parcel may become: one room piece, ink, stamp or seal.
public enum ParcelOffer: Codable, Hashable, Sendable {
  case ink(InkId)
  case item(RoomItemId)
  case postage(PostageId)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case ink, item, postage
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Ink": self = .ink(try container.decode(InkId.self, forKey: .ink))
    case "Item": self = .item(try container.decode(RoomItemId.self, forKey: .item))
    case "Postage": self = .postage(try container.decode(PostageId.self, forKey: .postage))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .ink(let ink):
      try container.encode("Ink", forKey: .tag)
      try container.encode(ink, forKey: .ink)
    case .item(let item):
      try container.encode("Item", forKey: .tag)
      try container.encode(item, forKey: .item)
    case .postage(let postage):
      try container.encode("Postage", forKey: .tag)
      try container.encode(postage, forKey: .postage)
    }
  }
}

/// `id` is `parcel:<transactionId>` or `parcel:<transactionId>:<month>`.
public struct Parcel: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let arrived: String

  public init(id: String, arrived: String) {
    self.id = id
    self.arrived = arrived
  }
}

/// `GET /v1/plus`. `parcels` wait to be opened, oldest first; `nextParcel` is absent when none is
/// due; `choicesLeft` is what a parcel could still become for this pair.
public struct PlusResponse: Codable, Hashable, Sendable {
  public let state: PlusState
  public let parcels: [Parcel]
  public let opened: Int
  public let nextParcel: String?
  public let bothPay: Bool
  public let choicesLeft: Int

  public init(
    state: PlusState, parcels: [Parcel], opened: Int, nextParcel: String? = nil,
    bothPay: Bool, choicesLeft: Int
  ) {
    self.state = state
    self.parcels = parcels
    self.opened = opened
    self.nextParcel = nextParcel
    self.bothPay = bothPay
    self.choicesLeft = choicesLeft
  }
}

/// A Plus plan's StoreKit 2 transaction as Apple signed it, and its renewal info when the phone
/// has it.
public struct SubscribeRequest: Codable, Hashable, Sendable {
  public let signedTransaction: String
  public let signedRenewalInfo: String?

  public init(signedTransaction: String, signedRenewalInfo: String? = nil) {
    self.signedTransaction = signedTransaction
    self.signedRenewalInfo = signedRenewalInfo
  }
}

/// Dev server only: what Apple would do to a Plus subscription.
public struct MockPlusRequest: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
    case subscribe, renew, cancel, fail, expire, refund
  }

  public let plan: PlusPlan
  public let transactionId: String
  public let kind: Kind

  public init(plan: PlusPlan, transactionId: String, kind: Kind) {
    self.plan = plan
    self.transactionId = transactionId
    self.kind = kind
  }
}

public struct OpenParcelRequest: Codable, Hashable, Sendable {
  public let parcel: String
  public let offer: ParcelOffer

  public init(parcel: String, offer: ParcelOffer) {
    self.parcel = parcel
    self.offer = offer
  }
}

public struct OpenParcelResponse: Codable, Hashable, Sendable {
  public let plus: PlusResponse
  public let shop: ShopResponse

  public init(plus: PlusResponse, shop: ShopResponse) {
    self.plus = plus
    self.shop = shop
  }
}
