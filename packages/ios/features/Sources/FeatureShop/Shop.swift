import Foundation

public enum ShopCategory: String, CaseIterable, Identifiable, Sendable {
  case today, furniture, decor, mochi, room, inks

  public var id: Self { self }

  func title(cat: String) -> String {
    switch self {
    case .today: "Today"
    case .furniture: "Furniture"
    case .decor: "Decor"
    case .mochi: "For \(cat)"
    case .room: "Room"
    case .inks: "Inks"
    }
  }

  var symbol: String {
    switch self {
    case .today: "sparkles"
    case .furniture: "chair.lounge.fill"
    case .decor: "leaf.fill"
    case .mochi: "pawprint.fill"
    case .room: "house.fill"
    case .inks: "paintpalette.fill"
    }
  }
}

public struct ShopItem: Identifiable, Hashable {
  public let id: String
  public let name: String
  public let price: Int
  let category: ShopCategory
  let blurb: String
  /// Mood chip the item nudges when it's in the room, e.g. a toy makes Mochi more curious.
  var mood: String? = nil
  var rarity: ShopRarity = .common
  var isPlus = false
  var isNew = false

  public var thumbnail: String { "Item_\(id)" }
}

/// Pieces that belong together; owning them all earns a coin bonus, collected once.
struct ShopCollection: Identifiable, Hashable {
  let id: String
  let name: String
  let itemIDs: [String]
  let bonus: Int

  func owned(of owned: Set<String>) -> Int { itemIDs.count { owned.contains($0) } }
  func isComplete(_ owned: Set<String>) -> Bool { itemIDs.allSatisfy(owned.contains) }
}

/// Bundled mock catalog. The copy calls the cat by the name given in onboarding, so every list takes `cat`.
public enum Catalog {
  public static func items(cat: String) -> [ShopItem] {
    [
      ShopItem(
        id: "armchair", name: "Cloud Armchair", price: 320, category: .furniture,
        blurb: "Big enough for two and a cat who insists.", mood: "Rested", rarity: .epic,
        isNew: true),
      ShopItem(
        id: "lamp", name: "Mushroom Lamp", price: 140, category: .decor,
        blurb: "Warm glow for late-night talks.", mood: "Rested", rarity: .rare),
      ShopItem(
        id: "monstera", name: "Monstera", price: 90, category: .decor,
        blurb: "Grows a new leaf every week you visit.", rarity: .common),
      ShopItem(
        id: "bookcase", name: "Little Bookcase", price: 260, category: .furniture,
        blurb: "Room for both your favourite stories.", rarity: .epic),
      ShopItem(
        id: "rug", name: "Woven Rug", price: 180, category: .room,
        blurb: "Soft rings in honey and blush.", rarity: .rare),
      ShopItem(
        id: "yarn", name: "Yarn Ball", price: 60, category: .mochi,
        blurb: "\(cat)'s favourite thing to unravel.", mood: "Curious", rarity: .common),
      ShopItem(
        id: "mouse", name: "Toy Mouse", price: 45, category: .mochi,
        blurb: "Squeaks a little. \(cat) pretends not to care.", mood: "Curious", rarity: .common),
      ShopItem(
        id: "tower", name: "Cat Tower", price: 540, category: .mochi,
        blurb: "Two floors, one nap spot at the very top.", mood: "Happy", rarity: .legendary,
        isPlus: true),
      ShopItem(
        id: "print", name: "Sunset Print", price: 120, category: .decor,
        blurb: "The sky from your first evening walk.", rarity: .rare),
      ShopItem(
        id: "teatable", name: "Tea Table", price: 210, category: .furniture,
        blurb: "Two cups, always.", rarity: .rare, isNew: true),
      ShopItem(
        id: "donutbed", name: "Donut Bed", price: 380, category: .mochi,
        blurb: "Sprinkles included, calories not.", mood: "Rested", rarity: .epic),
      ShopItem(
        id: "lantern", name: "Paper Lantern", price: 150, category: .room,
        blurb: "Hangs by the window and hums with light.", rarity: .legendary, isPlus: true),
    ]
  }

  static func collections(cat: String) -> [ShopCollection] {
    [
      ShopCollection(
        id: "cozy-autumn", name: "Cozy Autumn",
        itemIDs: ["lamp", "lantern", "armchair", "rug", "teatable", "print", "monstera"], bonus: 150
      ),
      ShopCollection(
        id: "mochis-corner", name: "\(cat)'s Corner",
        itemIDs: ["yarn", "mouse", "tower", "donutbed"], bonus: 100),
    ]
  }

  public static func item(_ id: String, cat: String) -> ShopItem? {
    items(cat: cat).first { $0.id == id }
  }

  /// The items of a category; Today is made of offers instead (ShopOffers).
  static func items(in category: ShopCategory, cat: String) -> [ShopItem] {
    items(cat: cat).filter { $0.category == category }
  }
}
