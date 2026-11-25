import Payments
import Testing

@testable import FeatureShop

@Suite struct ParcelChoicesTests {
  @Test func theDearestPiecesNeverComeInAParcel() {
    let ids = ParcelChoices.items(owned: [], cat: "Mochi").map(\.id)
    #expect(PlusCatalog.standard.parcelPriceCeiling == 320)
    #expect(!ids.contains("tower"))
    #expect(!ids.contains("donutbed"))
    #expect(ids.contains("teatable"))
  }

  @Test func whatThePairHasIsNotOffered() {
    let ids = ParcelChoices.items(owned: ["teatable", "lamp", "rug"], cat: "Mochi").map(\.id)
    #expect(!ids.contains("teatable"))
    #expect(!ids.contains("lamp"))
  }
}
