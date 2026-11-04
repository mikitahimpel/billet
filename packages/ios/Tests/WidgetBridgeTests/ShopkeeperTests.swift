import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct ShopkeeperTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func theTeddyKeepsTheShopUntilSomeoneChooses() {
    #expect(Shopkeeper.standard == .teddy)
    #expect(WidgetFeaturesStore(storage: storage()).loadShopkeeper() == .teddy)
  }

  @Test(arguments: Shopkeeper.allCases)
  func everyKeeperSurvivesTheStoreAndHasWords(_ keeper: Shopkeeper) throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveShopkeeper(keeper)
    #expect(store.loadShopkeeper() == keeper)
    #expect(!keeper.title.isEmpty)
    #expect(!keeper.detail.isEmpty)
  }

  @Test(arguments: ["tabby", "raccoon", "fox"])
  func aRetiredKeeperComesBackAsTheTeddy(_ retired: String) throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.shopkeeperFileName, Data("\"\(retired)\"".utf8))
    #expect(WidgetFeaturesStore(storage: storage).loadShopkeeperOverride() == .teddy)
    #expect(Shopkeeper.allCases == [.teddy, .human])
  }

  @Test func anUnknownKeeperGivesTheStandardOne() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.shopkeeperFileName, Data(#""badger""#.utf8))
    #expect(WidgetFeaturesStore(storage: storage).loadShopkeeper() == .standard)
  }

  @MainActor @Test func modelSavesTheChoiceWithoutRedrawingWidgets() {
    let store = WidgetFeaturesStore(storage: storage())
    var changes = 0
    let model = WidgetFeaturesModel(store: store) { changes += 1 }
    model.setShopkeeper(.human)
    #expect(model.shopkeeper == .human)
    #expect(WidgetFeaturesModel(store: store).shopkeeper == .human)
    #expect(changes == 0)
  }

  @Test func theNotesDeskAndTheShopAreNoLongerSwitches() {
    let keys = LabExperiment.allCases.map(\.rawValue)
    #expect(!keys.contains("notesDesk"))
    #expect(!keys.contains("shopScene"))
    #expect(WidgetFeatures.retiredKeys.contains("notesDesk"))
  }
}
