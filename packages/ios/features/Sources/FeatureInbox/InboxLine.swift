import Foundation
import Wire

/// What one Inbox row says: an SF Symbol and a short line, written on the phone from the item's
/// kind and payload. A shared mood shows its cat face in place of the symbol.
public struct InboxLine: Equatable {
  public let symbol: String
  public let text: String
  public var mood: CheckInMood?

  /// What the line needs from the rest of the app.
  public struct Names {
    /// The partner's name, as the profile has it.
    public let partner: String
    public let cat: String
    /// A shop item's or a set's title by its id; nil when the catalogue doesn't know it.
    public var title: (String) -> String?
    /// How a mood reads after "feels", such as "missing you".
    public var mood: (CheckInMood) -> String
    /// The SF Symbol of a list kind.
    public var list: (ListKind) -> String
    /// A reaction's emoji, as the server puts it in the push.
    public var reaction: (PhotoReaction) -> String

    public init(
      partner: String, cat: String, title: @escaping (String) -> String? = { _ in nil },
      mood: @escaping (CheckInMood) -> String = { $0.rawValue },
      list: @escaping (ListKind) -> String = { _ in "list.bullet" },
      reaction: @escaping (PhotoReaction) -> String = { $0.rawValue }
    ) {
      self.partner = partner
      self.cat = cat
      self.title = title
      self.mood = mood
      self.list = list
      self.reaction = reaction
    }
  }

  public init(symbol: String, text: String, mood: CheckInMood? = nil) {
    self.symbol = symbol
    self.text = text
    self.mood = mood
  }

  public init(_ item: ActivityItem, names: Names) {
    let who: String =
      switch item.actor {
      case .me: "You"
      case .partner: names.partner
      case .cat: names.cat
      case .store: "The App Store"
      }
    let cat = names.cat
    switch item.event {
    case .catFed(let grams):
      self.init(symbol: "fork.knife", text: "\(who) fed \(cat) \(grams) g")
    case .catPetted:
      self.init(symbol: "hand.raised.fill", text: "\(who) petted \(cat)")
    case .catPlayed:
      self.init(symbol: "sparkles", text: "\(who) played with \(cat)")
    case .catGamePlayed(let game, let score, let won):
      let name = names.title(game) ?? Self.readable(game)
      self.init(
        symbol: won ? "trophy.fill" : "gamecontroller.fill",
        text: "\(who) played \(name) with \(cat): \(score)" + (won ? ", and won" : ""))
    case .catSlept:
      self.init(symbol: "moon.zzz.fill", text: "\(cat) had a nap")
    case .catShooed:
      self.init(symbol: "hand.wave.fill", text: "\(who) shooed \(cat) off")
    case .plantWatered(let plant):
      let name = plant.map { (names.title($0) ?? Self.readable($0)).lowercased() } ?? "plant"
      self.init(symbol: "drop.fill", text: "\(who) watered the \(name)")
    case .catAdopted(let name):
      self.init(symbol: "heart.fill", text: "\(who) adopted \(name)")
    case .catRenamed(let name):
      self.init(symbol: "pencil", text: "\(who) named the cat \(name)")
    case .partnerJoined:
      let text = item.actor == .me ? "You joined \(names.partner)" : "\(who) joined you"
      self.init(symbol: "heart.circle.fill", text: text)
    case .reacted(_, let reaction):
      let text =
        item.actor == .me
        ? "You reacted \(names.reaction(reaction)) to a photo"
        : "\(who) reacted \(names.reaction(reaction)) to your photo"
      self.init(symbol: "face.smiling", text: text)
    case .moodShared(let mood):
      let feeling = names.mood(mood)
      let text = item.actor == .me ? "You feel \(feeling)" : "\(who) feels \(feeling)"
      self.init(symbol: "heart.text.square.fill", text: text, mood: mood)
    case .noteSent(_, let kind):
      let thing =
        switch kind {
        case "Drawing": "a drawing"
        case "Photo": "a photo"
        default: "a note"
        }
      let symbol =
        switch kind {
        case "Drawing": "scribble.variable"
        case "Photo": "photo.fill"
        default: "note.text"
        }
      let text = item.actor == .me ? "You sent \(thing)" : "\(who) sent you \(thing)"
      self.init(symbol: symbol, text: text)
    case .purchased(let offer, let items, let coins):
      let title =
        offer.flatMap(names.title) ?? (items.count == 1 ? items.first.flatMap(names.title) : nil)
      let what =
        title.map { "the \($0)" } ?? (items.count == 1 ? "something" : "\(items.count) things")
      self.init(symbol: "bag.fill", text: "\(who) bought \(what) for \(coins) coins")
    case .giftClaimed(let coins):
      self.init(
        symbol: "gift.fill", text: "\(who) opened the daily gift: \(Self.giftReward(coins))")
    case .bonusEarned(let collection, let coins):
      let name = names.title(collection) ?? Self.readable(collection)
      self.init(symbol: "star.fill", text: "\(who) finished \(name): +\(coins) coins")
    case .coinsBought(_, let coins):
      self.init(symbol: "dollarsign.circle.fill", text: "\(who) added \(coins) coins")
    case .refunded(_, let coins):
      self.init(symbol: "arrow.uturn.backward.circle.fill", text: "\(coins) coins were refunded")
    case .streakReached(let days):
      self.init(symbol: "flame.fill", text: "Your streak is \(days) days")
    case .listItemAdded(_, let kind, let title, let count, let text):
      let what = count == 1 ? "“\(text)”" : "\(count) items"
      self.init(symbol: names.list(kind), text: "\(who) added \(what) to \(title)")
    }
  }

  /// A gift that paid no coins gave a piece: its amount-0 entry names it.
  static func giftReward(_ coins: Int) -> String {
    switch coins {
    case ..<1: "a piece"
    case 1: "1 coin"
    default: "\(coins) coins"
    }
  }

  /// An id as words, for names the phone has no title for: `rainy-evening` → `Rainy evening`.
  public static func readable(_ id: String) -> String {
    let words = id.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }
}
