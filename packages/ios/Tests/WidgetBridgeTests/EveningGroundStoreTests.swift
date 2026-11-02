import DesignSystem
import Foundation
import Persistence
import Testing

@testable import WidgetBridge

@Suite struct EveningGroundStoreTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func nothingSavedGivesEmberDusk() {
    #expect(WidgetFeaturesStore(storage: storage()).loadEveningGround() == .ember)
  }

  @Test func aBrokenFileGivesTheStandardGround() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.eveningGroundFileName, Data("not json".utf8))
    #expect(WidgetFeaturesStore(storage: storage).loadEveningGround() == .standard)
  }

  @MainActor @Test func aChosenGroundIsSavedAndRedrawsTheWidgets() {
    let store = WidgetFeaturesStore(storage: storage())
    var changes = 0
    let model = WidgetFeaturesModel(store: store) { changes += 1 }
    model.setEveningGround(.cocoa)
    #expect(model.eveningGround == .cocoa)
    #expect(WidgetFeaturesModel(store: store).eveningGround == .cocoa)
    #expect(changes == 1)
    model.setEveningGround(.cocoa)
    #expect(changes == 1)
  }
}
