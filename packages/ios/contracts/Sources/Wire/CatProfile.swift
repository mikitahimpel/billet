/// Ids from the app's own catalog.
public struct CatLook: Codable, Hashable, Sendable {
  public let model: String
  public let coat: String

  public init(model: String, coat: String) {
    self.model = model
    self.coat = coat
  }
}

/// `bornAt` (epoch milliseconds) and `natureSeed` are set once, at adoption. `natureSeed` is a
/// decimal UInt64 seeding the cat's nature on both phones; moment-to-moment choices use a seed
/// each phone draws at launch.
public struct CatProfile: Codable, Hashable, Sendable {
  public let name: String
  public let look: CatLook
  public let bornAt: Int
  public let natureSeed: String
  /// The pair's clock, for the hour the cat's day rhythm reads.
  public let utcOffsetSeconds: Int

  public init(
    name: String, look: CatLook, bornAt: Int, natureSeed: String, utcOffsetSeconds: Int
  ) {
    self.name = name
    self.look = look
    self.bornAt = bornAt
    self.natureSeed = natureSeed
    self.utcOffsetSeconds = utcOffsetSeconds
  }

  public var seed: UInt64? { UInt64(natureSeed) }
}

/// Each from 0.1 to 0.9, 0.5 at adoption.
public struct CatTemper: Codable, Hashable, Sendable {
  public let curious: Double
  public let lazy: Double
  public let cuddly: Double

  public init(curious: Double, lazy: Double, cuddly: Double) {
    self.curious = curious
    self.lazy = lazy
    self.cuddly = cuddly
  }
}

/// At `at` (epoch milliseconds), folded on the server with `PetLife`'s curves.
public struct CatNeeds: Codable, Hashable, Sendable {
  public let at: Int
  public let full: Double
  public let rested: Double
  public let loved: Double
  public let playful: Double
  public let mood: Double
  public let asleep: Bool
  /// Set when one partner has cared for the cat much less than the other.
  public let missing: UserId?

  public init(
    at: Int, full: Double, rested: Double, loved: Double, playful: Double, mood: Double,
    asleep: Bool, missing: UserId? = nil
  ) {
    self.at = at
    self.full = full
    self.rested = rested
    self.loved = loved
    self.playful = playful
    self.mood = mood
    self.asleep = asleep
    self.missing = missing
  }

  private enum CodingKeys: String, CodingKey {
    case at
    case full
    case rested
    case loved
    case playful
    case mood
    case asleep
    case missing
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    at = try container.decode(Int.self, forKey: .at)
    full = try container.decode(Double.self, forKey: .full)
    rested = try container.decode(Double.self, forKey: .rested)
    loved = try container.decode(Double.self, forKey: .loved)
    playful = try container.decode(Double.self, forKey: .playful)
    mood = try container.decode(Double.self, forKey: .mood)
    asleep = try container.decode(Bool.self, forKey: .asleep)
    missing = try container.decodeOptionalKey(UserId.self, forKey: .missing)
  }
}
