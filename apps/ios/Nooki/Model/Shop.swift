import SwiftUI

enum ShopCategory: String, CaseIterable, Identifiable {
    case today, furniture, decor, mochi, room

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .furniture: "Furniture"
        case .decor: "Decor"
        case .mochi: "For Mochi"
        case .room: "Room"
        }
    }
}

struct ShopItem: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let category: ShopCategory
    let blurb: String
    /// Mood chip the item nudges when it's in the room, e.g. a toy makes Mochi more curious.
    var mood: String? = nil
    var isPlus = false
    var isNew = false

    var thumbnail: String { "Item_\(id)" }
}

struct ShopCollection {
    let name: String
    let subtitle: String
    let itemIDs: [String]
}

/// Bundled mock catalog; later served as catalog.json (see docs/shop-concept.md).
enum Catalog {
    static let items: [ShopItem] = [
        ShopItem(id: "armchair", name: "Cloud Armchair", price: 320, category: .furniture,
                 blurb: "Big enough for two and a cat who insists.", mood: "Rested", isNew: true),
        ShopItem(id: "lamp", name: "Mushroom Lamp", price: 140, category: .decor,
                 blurb: "Warm glow for late-night talks.", mood: "Rested"),
        ShopItem(id: "monstera", name: "Monstera", price: 90, category: .decor,
                 blurb: "Grows a new leaf every week you visit."),
        ShopItem(id: "bookcase", name: "Little Bookcase", price: 260, category: .furniture,
                 blurb: "Room for both your favourite stories."),
        ShopItem(id: "rug", name: "Woven Rug", price: 180, category: .room,
                 blurb: "Soft rings in honey and blush."),
        ShopItem(id: "yarn", name: "Yarn Ball", price: 60, category: .mochi,
                 blurb: "Mochi's favourite thing to unravel.", mood: "Curious"),
        ShopItem(id: "mouse", name: "Toy Mouse", price: 45, category: .mochi,
                 blurb: "Squeaks a little. Mochi pretends not to care.", mood: "Curious"),
        ShopItem(id: "tower", name: "Cat Tower", price: 540, category: .mochi,
                 blurb: "Two floors, one nap spot at the very top.", mood: "Happy", isPlus: true),
        ShopItem(id: "print", name: "Sunset Print", price: 120, category: .decor,
                 blurb: "The sky from your first evening walk."),
        ShopItem(id: "teatable", name: "Tea Table", price: 210, category: .furniture,
                 blurb: "Two cups, always.", isNew: true),
        ShopItem(id: "donutbed", name: "Donut Bed", price: 380, category: .mochi,
                 blurb: "Sprinkles included, calories not.", mood: "Rested"),
        ShopItem(id: "lantern", name: "Paper Lantern", price: 150, category: .room,
                 blurb: "Hangs by the window and hums with light.", isPlus: true),
    ]

    static let todayIDs = ["armchair", "yarn", "lantern", "teatable"]
    /// One of today's items is discounted; rotates daily on the server.
    static let dealID = "armchair"
    static let dealDiscount = 0.2

    static let featured = ShopCollection(
        name: "Cozy Cabin",
        subtitle: "Collect all 4 for a fireplace glow",
        itemIDs: ["lamp", "teatable", "rug", "lantern"]
    )

    static func item(_ id: String) -> ShopItem? { items.first { $0.id == id } }

    static func items(in category: ShopCategory) -> [ShopItem] {
        category == .today ? todayIDs.compactMap(item) : items.filter { $0.category == category }
    }

    static func price(of item: ShopItem) -> Int {
        item.id == dealID ? Int((Double(item.price) * (1 - dealDiscount)).rounded()) : item.price
    }
}
