import Foundation
import ShopInterface
import Wire

struct CoinLine: Hashable {
  let symbol: String
  let title: String
  let amount: String
  let isGain: Bool
  let date: Date

  init(_ entry: CoinEntry, offers: ShopOffers) {
    date = Date(timeIntervalSince1970: Double(entry.at) / 1000)
    isGain = entry.amount >= 0
    amount = entry.amount > 0 ? "+\(entry.amount)" : entry.amount < 0 ? "−\(-entry.amount)" : "0"
    switch entry.kind {
    case .earn:
      symbol = "sparkles"
      title = Self.earned(entry.id)
    case .buy:
      symbol = "creditcard.fill"
      title = "Coins bought"
    case .spend:
      symbol = "bag.fill"
      title = Self.name(of: entry.ref, offers: offers)
    case .refund:
      symbol = "arrow.uturn.backward"
      title = "Refund"
    case .gift:
      symbol = "gift.fill"
      if entry.ref == "welcome" {
        title = "Welcome coins"
      } else if entry.amount == 0 {
        title = "Daily gift: \(Self.name(of: entry.ref, offers: offers))"
      } else {
        title = "Daily gift"
      }
    case .bonus:
      symbol = "checkmark.seal.fill"
      title =
        "\(Catalog.collections(cat: offers.cat).first { $0.id == entry.ref }?.name ?? "Collection") bonus"
    }
  }

  /// App earns are `earn:<what>:<ref>`; the room's own, for notes and care, are `earn:<entry>`.
  static func earned(_ id: String) -> String {
    let parts = id.split(separator: ":")
    guard parts.count >= 3 else { return "Notes and care" }
    switch parts[1] {
    case "wish": return "A wish came true"
    case "date": return "A date you both liked"
    case "plan": return "A date, rated"
    case "list": return "Ticked off a list"
    case "moment": return "A moment"
    case "note": return "A note"
    case "guess": return "Guessed right in Who knows who"
    case "round": return "Played Who knows who"
    case "streak": return "A day of your love streak"
    default: return "Coins earned"
    }
  }

  static func name(of ref: String, offers: ShopOffers) -> String {
    if ref == "treat" { return "A treat" }
    if let item = Catalog.item(ref, cat: offers.cat) { return item.name }
    if let bundle = offers.bundles.first(where: { $0.id == ref }) {
      return bundle.name
    }
    if let set = ShopOffers.featuredSets.first(where: { $0.id == ref }) { return set.name }
    if let ink = PaletteInk.bundled.first(where: { $0.id == ref }) { return "\(ink.name) ink" }
    return ref
  }
}
