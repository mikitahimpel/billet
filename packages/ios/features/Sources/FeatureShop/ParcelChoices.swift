import Foundation
import Payments

/// What a parcel may become in this build's Shop: every piece on sale that the pair hasn't got, up
/// to the ceiling's price, dearest first. The server holds the same rule (`parcelChoices`).
enum ParcelChoices {
  static func items(
    owned: Set<String>, cat: String, ceiling: Int = PlusCatalog.standard.parcelPriceCeiling
  ) -> [ShopItem] {
    Catalog.items(cat: cat)
      .filter { $0.price > 0 && $0.price <= ceiling && !owned.contains($0.id) }
      .sorted { $0.price > $1.price }
  }
}
