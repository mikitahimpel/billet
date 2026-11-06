import Foundation

/// The icon a list item gets from its words: places to eat, books and bucket-list dreams first, then the grocery
/// catalog's aisle, then the list's own icon.
nonisolated enum ItemIcon {
    private struct Match {
        let stems: [String]
        let glyph: UsGlyph
    }

    static func glyph(for text: String, list: UsGlyph, catalog: GroceryCatalog = .bundled) -> UsGlyph {
        let stems = GroceryWords.stems(text)
        guard !stems.isEmpty else { return list }
        if let match = matches.first(where: { contains(stems, $0.stems) }) { return match.glyph }
        if let entry = catalog.entry(for: text) { return entry.aisle.icon }
        return list
    }

    private static func contains(_ stems: [String], _ phrase: [String]) -> Bool {
        guard phrase.count <= stems.count else { return false }
        return (0...(stems.count - phrase.count)).contains { start in
            Array(stems[start..<(start + phrase.count)]) == phrase
        }
    }

    /// Every symbol the table uses, so a test can check each one exists.
    static var symbols: Set<String> { Set(table.map(\.glyph.symbol)) }

    /// The most words first, so "ice cream" wins over "cream".
    private static let matches: [Match] = table
        .flatMap { entry in entry.words.map { Match(stems: GroceryWords.stems($0), glyph: entry.glyph) } }
        .sorted { $0.stems.count > $1.stems.count }

    private static let table: [(words: [String], glyph: UsGlyph)] = [
        // Places to eat.
        (["coffee", "cafe", "café", "espresso", "latte", "brunch"], .init(symbol: "cup.and.saucer.fill", tint: .honey)),
        (["tea", "teahouse"], .init(symbol: "mug.fill", tint: .sage)),
        (["bar", "pub", "cocktail", "wine", "winery", "brewery", "beer"], .init(symbol: "wineglass.fill", tint: .lilac)),
        (["sushi", "seafood", "oyster", "fish"], .init(symbol: "fish.fill", tint: .coral)),
        (["burger", "fries", "taco", "kebab", "takeout", "food truck", "hot dog"],
         .init(symbol: "takeoutbag.and.cup.and.straw.fill", tint: .honey)),
        (["bakery", "cake", "dessert", "pastry", "patisserie", "donut", "ice cream", "gelato"],
         .init(symbol: "birthday.cake.fill", tint: .sun)),
        (["steak", "steakhouse", "bbq", "barbecue", "grill", "korean bbq"], .init(symbol: "flame.fill", tint: .coral)),
        (["vegan", "vegetarian", "salad", "plant based"], .init(symbol: "leaf.fill", tint: .sage)),
        (["pizza", "pizzeria", "pasta", "trattoria", "ramen", "noodle", "pho", "restaurant", "bistro", "diner",
          "dinner", "tasting menu"], .init(symbol: "fork.knife", tint: .honey)),
        // Books.
        (["book", "novel", "series", "trilogy"], .init(symbol: "book.fill", tint: .lilac)),
        (["poem", "poetry", "poems"], .init(symbol: "text.quote", tint: .blush)),
        (["cookbook", "recipe", "recipes"], .init(symbol: "frying.pan.fill", tint: .honey)),
        (["comic", "manga", "graphic novel"], .init(symbol: "bubble.left.and.bubble.right.fill", tint: .sky)),
        (["audiobook", "podcast"], .init(symbol: "headphones", tint: .lilac)),
        (["mystery", "detective", "thriller", "crime"], .init(symbol: "magnifyingglass", tint: .sky)),
        (["history", "biography", "memoir", "science"], .init(symbol: "graduationcap.fill", tint: .sun)),
        // Bucket list.
        (["balloon", "hot air"], .init(symbol: "balloon.fill", tint: .coral)),
        (["skydive", "skydiving", "paraglide", "paragliding", "fly", "flight", "trip", "travel"],
         .init(symbol: "airplane", tint: .sky)),
        (["concert", "festival", "music", "gig", "band"], .init(symbol: "music.note", tint: .lilac)),
        (["beach", "island", "tropical"], .init(symbol: "beach.umbrella.fill", tint: .sun)),
        (["mountain", "hike", "hiking", "climb", "climbing", "volcano", "summit"],
         .init(symbol: "mountain.2.fill", tint: .sage)),
        (["camp", "camping", "tent", "glamping"], .init(symbol: "tent.fill", tint: .sage)),
        (["ski", "skiing", "snowboard", "snow"], .init(symbol: "snowflake", tint: .sky)),
        (["dive", "diving", "scuba", "snorkel", "snorkeling", "swim", "surf", "surfing", "kayak"],
         .init(symbol: "water.waves", tint: .sky)),
        (["northern lights", "aurora", "stars", "stargazing", "eclipse"], .init(symbol: "moon.stars.fill", tint: .lilac)),
        (["road trip", "drive", "car"], .init(symbol: "car.fill", tint: .honey)),
        (["sail", "sailing", "boat", "cruise", "yacht"], .init(symbol: "sailboat.fill", tint: .sky)),
        (["dance", "dancing", "salsa", "tango"], .init(symbol: "figure.dance", tint: .blush)),
        (["photo", "photography", "photoshoot"], .init(symbol: "camera.fill", tint: .sky)),
        (["wedding", "marry", "vow", "vows", "proposal"], .init(symbol: "heart.fill", tint: .blush)),
        (["dog", "puppy", "cat", "kitten", "pet", "horse"], .init(symbol: "pawprint.fill", tint: .honey)),
        (["marathon", "run", "running", "race"], .init(symbol: "figure.run", tint: .coral)),
        (["theater", "theatre", "opera", "musical", "ballet", "broadway"],
         .init(symbol: "theatermasks.fill", tint: .blush)),
        (["museum", "gallery", "exhibition"], .init(symbol: "building.columns.fill", tint: .sun)),
        (["garden", "plant", "plants", "tree"], .init(symbol: "leaf.fill", tint: .sage)),
        (["house", "home", "apartment", "move in"], .init(symbol: "house.fill", tint: .honey)),
        (["paint", "painting", "pottery", "tattoo", "draw"], .init(symbol: "paintbrush.fill", tint: .coral)),
        (["game", "games", "arcade", "escape room"], .init(symbol: "gamecontroller.fill", tint: .lilac)),
    ]
}
