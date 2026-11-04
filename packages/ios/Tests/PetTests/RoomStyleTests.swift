import Foundation
import Testing

@testable import Pet

@Suite("Room style")
struct RoomStyleTests {
  @Test func eachPartDecodesOnItsOwnAndUnknownChoicesReadAsStandard() throws {
    let json = Data(#"{"wall":"sage","floor":"marble","curtains":"linen","drape":7,"view":"moonBase"}"#.utf8)
    let style = try JSONDecoder().decode(RoomStyle.self, from: json)
    #expect(style.wall == .sage)
    #expect(style.floor == .standard)
    #expect(style.curtains == .linen)
    #expect(style.drape == .standard)
    #expect(style.view == nil)
    #expect(style.fairy == .standard)
    #expect(try JSONDecoder().decode(RoomStyle.self, from: Data("{}".utf8)) == .standard)
  }

  @Test func roundTripsThroughCodable() throws {
    let style = RoomStyle(
      wall: .trellis, floor: .herringbone, curtains: .gingham, drape: .half, view: .mistyLake,
      fairy: .ice)
    let data = try JSONEncoder().encode(style)
    #expect(try JSONDecoder().decode(RoomStyle.self, from: data) == style)
  }

  @Test func aChoiceGoesIntoItsOwnPartOnly() {
    let style = RoomStyle.standard.with(.wall(.rose)).with(.fairy(.mint)).with(.view(.pinkDusk))
    #expect(style.wall == .rose)
    #expect(style.fairy == .mint)
    #expect(style.view == .pinkDusk)
    #expect(style.floor == .standard)
    #expect(style.shows(.wall(.rose)))
    #expect(!style.shows(.wall(.sage)))
    #expect(style.with(.view(nil)).view == nil)
  }

  @Test func theStandardLookOfEveryPartIsFreeAndSomeOfEachCostStamps() {
    let standard: [RoomStyleItem] = [
      .wall(.standard), .floor(.standard), .curtains(.standard), .view(nil), .fairy(.standard),
    ]
    for item in standard { #expect(item.price == nil) }
    let free = RoomStyleItem.all.filter { $0.price == nil }
    let paid = RoomStyleItem.all.filter { $0.price != nil }
    #expect(free.count >= 15)
    #expect(paid.count >= 15)
    #expect(paid.allSatisfy { ($0.price ?? 0) > 0 && $0.shopItem?.price == $0.price })
    #expect(free.allSatisfy { $0.shopItem == nil })
  }

  @Test func theStyleTabOffersWhatTheOwnerAskedFor() {
    let paints = RoomWall.allCases.filter { !$0.isWallpaper }
    let papers = RoomWall.allCases.filter(\.isWallpaper)
    #expect((8...10).contains(paints.count))
    #expect((4...6).contains(papers.count))
    #expect(Set(RoomFloor.allCases).isSuperset(of: [.lightWood, .darkWood, .herringbone, .tiles]))
    #expect(CurtainDrape.allCases == [.open, .half, .closed])
    for view in WindowView.allCases { #expect(RoomStyleItem.all.contains(.view(view))) }
  }

  @Test func everyChoiceHasItsOwnShopID() {
    let ids = RoomStyleItem.all.map(\.shopID)
    #expect(Set(ids).count == ids.count)
    #expect(Set(ShopCatalog.standard.items.map(\.id)).isDisjoint(with: ids))
  }

  @Test func pairPlayKeepsTheStyleAndOlderSavesReadAsStandard() throws {
    var play = PairPlay(device: "a")
    let style = RoomStyle(wall: .peach, curtains: .rose, drape: .closed)
    play.style(style)
    let saved = try JSONDecoder().decode(
      PairPlay.Saved.self, from: JSONEncoder().encode(play.saved))
    #expect(PairPlay(device: "a", saved: saved).roomStyle == style)
    var older = saved
    older.roomStyle = nil
    #expect(PairPlay(device: "a", saved: older).roomStyle == .standard)
  }

  @MainActor
  @Test func unlockingAStyleSpendsItsStampsOnce() throws {
    let shop = ShopStore(storage: .memory(), grant: 20)
    let renovator = RoomRenovator(store: shop)
    let teal = RoomStyleItem.wall(.teal)
    #expect(renovator.hasUnlocked(.wall(.sage)))
    #expect(!renovator.hasUnlocked(teal))
    try renovator.unlock(teal)
    #expect(renovator.hasUnlocked(teal))
    #expect(renovator.stamps == 20 - (teal.price ?? 0))
    try renovator.unlock(teal)
    #expect(renovator.stamps == 20 - (teal.price ?? 0))
    #expect(throws: ShopError.self) { try renovator.unlock(.floor(.herringbone)) }
    #expect(!renovator.hasUnlocked(.floor(.herringbone)))
  }
}
