import Foundation
import MomentsInterface
import ProfileInterface
import UsInterface
import WidgetInterface
import WidgetUI

/// A store section. The raw value is the slug kept in a list item's `aisle`.
nonisolated enum GroceryAisle: String, CaseIterable, Codable, Identifiable {
  case produce, dairy, bakery, meat, frozen, drinks, pantry, household, pet, other

  var id: String { rawValue }

  var title: String {
    switch self {
    case .produce: "Fruit & veg"
    case .dairy: "Dairy"
    case .bakery: "Bakery"
    case .meat: "Meat & fish"
    case .frozen: "Frozen"
    case .drinks: "Drinks"
    case .pantry: "Pantry"
    case .household: "Household"
    case .pet: "For \(CatProfile.name())"
    case .other: "Other"
    }
  }

  var icon: UsGlyph {
    switch self {
    case .produce: .init(symbol: "carrot.fill", tint: .sage)
    case .dairy: .init(symbol: "drop.fill", tint: .sky)
    case .bakery: .init(symbol: "birthday.cake.fill", tint: .sun)
    case .meat: .init(symbol: "fish.fill", tint: .coral)
    case .frozen: .init(symbol: "snowflake", tint: .sky)
    case .drinks: .init(symbol: "wineglass.fill", tint: .lilac)
    case .pantry: .init(symbol: "frying.pan.fill", tint: .honey)
    case .household: .init(symbol: "bubbles.and.sparkles.fill", tint: .lilac)
    case .pet: .init(symbol: "pawprint.fill", tint: .honey)
    case .other: .init(symbol: "bag.fill", tint: .blush)
    }
  }
}

/// A product a partner may mean while typing.
nonisolated struct GrocerySuggestion: Hashable, Identifiable {
  var text: String
  var aisle: GroceryAisle

  var id: String { GroceryWords.key(text) }
}

/// `GroceryCatalog.json`: about 300 products in English and Russian, each with its aisle.
nonisolated struct GroceryCatalog {
  struct Entry: Codable, Hashable {
    struct Words: Codable, Hashable {
      var en: [String]
      var ru: [String]
    }

    var words: Words
    var aisle: GroceryAisle
  }

  let entries: [Entry]
  /// Every name's stems with its entry, the most words first, then the longest, so "oat milk" wins over "milk".
  private let phrases: [(stems: [String], entry: Entry)]

  init(entries: [Entry]) {
    self.entries = entries
    phrases =
      entries
      .flatMap { entry in (entry.words.en + entry.words.ru).map { (GroceryWords.stems($0), entry) }
      }
      .sorted {
        ($0.stems.count, $0.stems.joined().count) > ($1.stems.count, $1.stems.joined().count)
      }
  }

  static let bundled: GroceryCatalog = {
    guard let url = Bundle.main.url(forResource: "GroceryCatalog", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let entries = try? JSONDecoder().decode([Entry].self, from: data)
    else { return GroceryCatalog(entries: []) }
    return GroceryCatalog(entries: entries)
  }()

  /// The product named anywhere in `text`, by the longest name it contains.
  func entry(for text: String) -> Entry? {
    let stems = GroceryWords.stems(text)
    guard !stems.isEmpty else { return nil }
    return phrases.first { phrase in
      phrase.stems.count <= stems.count
        && (0...(stems.count - phrase.stems.count)).contains { start in
          Array(stems[start..<(start + phrase.stems.count)]) == phrase.stems
        }
    }?.entry
  }

  /// What the pair picked for the name before, then the catalog; a name it doesn't know goes to "Other".
  func aisle(for text: String, history: GroceryHistory = GroceryHistory()) -> GroceryAisle {
    history.entry(for: text)?.aisle.flatMap(GroceryAisle.init(rawValue:)) ?? entry(for: text)?.aisle
      ?? .other
  }

  /// The item's own pick first.
  func aisle(for item: ListItem, history: GroceryHistory) -> GroceryAisle {
    item.aisle.flatMap(GroceryAisle.init(rawValue:)) ?? aisle(for: item.text, history: history)
  }

  /// Names starting with what is typed, in its alphabet: whole names first, then a later word, shortest first. The
  /// pair's own names come before the catalog's at the same rank.
  func suggestions(for typed: String, history: GroceryHistory = GroceryHistory(), limit: Int)
    -> [GrocerySuggestion]
  {
    let query = GroceryWords.words(typed).joined(separator: " ")
    guard !query.isEmpty else { return [] }
    let russian = GroceryWords.isCyrillic(query)
    func rank(_ name: String) -> Int? {
      let words = GroceryWords.words(name)
      if words.joined(separator: " ").hasPrefix(query) { return 0 }
      return words.dropFirst().contains { $0.hasPrefix(query) } ? 1 : nil
    }
    var ranked: [(rank: Int, suggestion: GrocerySuggestion)] = []
    for entry in history.often(limit: .max) where GroceryWords.isCyrillic(entry.text) == russian {
      guard let rank = rank(entry.text) else { continue }
      ranked.append(
        (
          rank * 2,
          GrocerySuggestion(text: entry.text, aisle: aisle(for: entry.text, history: history))
        ))
    }
    for entry in entries {
      for name in russian ? entry.words.ru : entry.words.en {
        guard let rank = rank(name) else { continue }
        let text = name.prefix(1).uppercased() + name.dropFirst()
        ranked.append((rank * 2 + 1, GrocerySuggestion(text: text, aisle: entry.aisle)))
      }
    }
    var seen: Set<String> = []
    return
      ranked
      .sorted {
        ($0.rank, $0.suggestion.text.count, $0.suggestion.text) < (
          $1.rank, $1.suggestion.text.count, $1.suggestion.text
        )
      }
      .map(\.suggestion)
      .filter { seen.insert($0.id).inserted }
      .prefix(limit)
      .map { $0 }
  }
}
