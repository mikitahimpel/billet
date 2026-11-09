/// The phone writes the line in its own language from the kind and these values, and localises
/// shop items, collections, games and plants by id.
public enum ActivityEvent: Codable, Hashable, Sendable {
  case catFed(grams: Int)
  case catPetted
  case catPlayed
  /// `game` is a mini-game id such as `laser`.
  case catGamePlayed(game: String, score: Int, won: Bool)
  case catSlept
  case catShooed
  /// `plant` is `nil` for the one plant by the window that came before plants had ids.
  case plantWatered(plant: String?)
  case catAdopted(name: String)
  case catRenamed(name: String)
  case partnerJoined
  /// `kind` is the note's `_tag`: `Drawing`, `Photo` or `Text`.
  case noteSent(note: NoteId, kind: String)
  case reacted(note: NoteId, reaction: PhotoReaction)
  case moodShared(mood: CheckInMood)
  /// `offer` is set when the buy was a bundle or a deal; `items` is never empty.
  case purchased(offer: String?, items: [String], coins: Int)
  case giftClaimed(coins: Int)
  case bonusEarned(collection: String, coins: Int)
  case coinsBought(productId: String, coins: Int)
  case refunded(productId: String, coins: Int)
  case streakReached(days: Int)
  /// The partner added `count` items to one list within ten minutes; `text` is the latest.
  case listItemAdded(list: IdempotencyKey, kind: ListKind, title: String, count: Int, text: String)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case grams
    case game
    case score
    case won
    case plant
    case name
    case note
    case kind
    case reaction
    case mood
    case offer
    case items
    case coins
    case collection
    case productId
    case days
    case list
    case title
    case count
    case text
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "CatFed":
      self = .catFed(grams: try container.decode(Int.self, forKey: .grams))
    case "CatPetted":
      self = .catPetted
    case "CatPlayed":
      self = .catPlayed
    case "CatGamePlayed":
      self = .catGamePlayed(
        game: try container.decode(String.self, forKey: .game),
        score: try container.decode(Int.self, forKey: .score),
        won: try container.decode(Bool.self, forKey: .won))
    case "CatSlept":
      self = .catSlept
    case "CatShooed":
      self = .catShooed
    case "PlantWatered":
      self = .plantWatered(plant: try container.decodeOptionalKey(String.self, forKey: .plant))
    case "CatAdopted":
      self = .catAdopted(name: try container.decode(String.self, forKey: .name))
    case "CatRenamed":
      self = .catRenamed(name: try container.decode(String.self, forKey: .name))
    case "PartnerJoined":
      self = .partnerJoined
    case "NoteSent":
      self = .noteSent(
        note: try container.decode(NoteId.self, forKey: .note),
        kind: try container.decode(String.self, forKey: .kind))
    case "Reacted":
      self = .reacted(
        note: try container.decode(NoteId.self, forKey: .note),
        reaction: try container.decode(PhotoReaction.self, forKey: .reaction))
    case "MoodShared":
      self = .moodShared(mood: try container.decode(CheckInMood.self, forKey: .mood))
    case "Purchased":
      self = .purchased(
        offer: try container.decodeOptionalKey(String.self, forKey: .offer),
        items: try container.decode([String].self, forKey: .items),
        coins: try container.decode(Int.self, forKey: .coins))
    case "GiftClaimed":
      self = .giftClaimed(coins: try container.decode(Int.self, forKey: .coins))
    case "BonusEarned":
      self = .bonusEarned(
        collection: try container.decode(String.self, forKey: .collection),
        coins: try container.decode(Int.self, forKey: .coins))
    case "CoinsBought":
      self = .coinsBought(
        productId: try container.decode(String.self, forKey: .productId),
        coins: try container.decode(Int.self, forKey: .coins))
    case "Refunded":
      self = .refunded(
        productId: try container.decode(String.self, forKey: .productId),
        coins: try container.decode(Int.self, forKey: .coins))
    case "StreakReached":
      self = .streakReached(days: try container.decode(Int.self, forKey: .days))
    case "ListItemAdded":
      self = .listItemAdded(
        list: try container.decode(IdempotencyKey.self, forKey: .list),
        kind: try container.decode(ListKind.self, forKey: .kind),
        title: try container.decode(String.self, forKey: .title),
        count: try container.decode(Int.self, forKey: .count),
        text: try container.decode(String.self, forKey: .text))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .catFed(let grams):
      try container.encode("CatFed", forKey: .tag)
      try container.encode(grams, forKey: .grams)
    case .catPetted:
      try container.encode("CatPetted", forKey: .tag)
    case .catPlayed:
      try container.encode("CatPlayed", forKey: .tag)
    case .catGamePlayed(let game, let score, let won):
      try container.encode("CatGamePlayed", forKey: .tag)
      try container.encode(game, forKey: .game)
      try container.encode(score, forKey: .score)
      try container.encode(won, forKey: .won)
    case .catSlept:
      try container.encode("CatSlept", forKey: .tag)
    case .catShooed:
      try container.encode("CatShooed", forKey: .tag)
    case .plantWatered(let plant):
      try container.encode("PlantWatered", forKey: .tag)
      try container.encodeIfPresent(plant, forKey: .plant)
    case .catAdopted(let name):
      try container.encode("CatAdopted", forKey: .tag)
      try container.encode(name, forKey: .name)
    case .catRenamed(let name):
      try container.encode("CatRenamed", forKey: .tag)
      try container.encode(name, forKey: .name)
    case .partnerJoined:
      try container.encode("PartnerJoined", forKey: .tag)
    case .noteSent(let note, let kind):
      try container.encode("NoteSent", forKey: .tag)
      try container.encode(note, forKey: .note)
      try container.encode(kind, forKey: .kind)
    case .reacted(let note, let reaction):
      try container.encode("Reacted", forKey: .tag)
      try container.encode(note, forKey: .note)
      try container.encode(reaction, forKey: .reaction)
    case .moodShared(let mood):
      try container.encode("MoodShared", forKey: .tag)
      try container.encode(mood, forKey: .mood)
    case .purchased(let offer, let items, let coins):
      try container.encode("Purchased", forKey: .tag)
      try container.encodeIfPresent(offer, forKey: .offer)
      try container.encode(items, forKey: .items)
      try container.encode(coins, forKey: .coins)
    case .giftClaimed(let coins):
      try container.encode("GiftClaimed", forKey: .tag)
      try container.encode(coins, forKey: .coins)
    case .bonusEarned(let collection, let coins):
      try container.encode("BonusEarned", forKey: .tag)
      try container.encode(collection, forKey: .collection)
      try container.encode(coins, forKey: .coins)
    case .coinsBought(let productId, let coins):
      try container.encode("CoinsBought", forKey: .tag)
      try container.encode(productId, forKey: .productId)
      try container.encode(coins, forKey: .coins)
    case .refunded(let productId, let coins):
      try container.encode("Refunded", forKey: .tag)
      try container.encode(productId, forKey: .productId)
      try container.encode(coins, forKey: .coins)
    case .streakReached(let days):
      try container.encode("StreakReached", forKey: .tag)
      try container.encode(days, forKey: .days)
    case .listItemAdded(let list, let kind, let title, let count, let text):
      try container.encode("ListItemAdded", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(kind, forKey: .kind)
      try container.encode(title, forKey: .title)
      try container.encode(count, forKey: .count)
      try container.encode(text, forKey: .text)
    }
  }
}
