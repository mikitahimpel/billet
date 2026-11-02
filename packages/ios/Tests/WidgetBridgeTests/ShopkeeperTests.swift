import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct ShopkeeperTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func theOldTabbyKeepsTheShopUntilSomeoneChooses() {
    #expect(Shopkeeper.standard == .tabby)
    #expect(WidgetFeaturesStore(storage: storage()).loadShopkeeper() == .tabby)
  }

  @Test(arguments: Shopkeeper.allCases)
  func everyKeeperSurvivesTheStoreAndHasWords(_ keeper: Shopkeeper) throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveShopkeeper(keeper)
    #expect(store.loadShopkeeper() == keeper)
    #expect(!keeper.title.isEmpty)
    #expect(!keeper.detail.isEmpty)
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
    model.setShopkeeper(.fox)
    #expect(model.shopkeeper == .fox)
    #expect(WidgetFeaturesModel(store: store).shopkeeper == .fox)
    #expect(changes == 0)
  }

  @Test func theTabScenesAreLabsSwitchesThatStartOn() {
    #expect(LabExperiment.shopScene.defaultOn)
    #expect(LabExperiment.notesDesk.defaultOn)
    #expect(!LabExperiment.shopScene.hasHomeCard)
    #expect(LabExperiment.notesDesk.group == .notes)
  }
}
