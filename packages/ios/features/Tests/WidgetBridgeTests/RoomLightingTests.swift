import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct RoomLightingTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func theStandardLightingIsTheAmberLantern() {
    #expect(RoomLighting.standard == .amberLantern)
  }

  @Test func nothingSavedGivesTheStandardLighting() {
    #expect(WidgetFeaturesStore(storage: storage()).loadLighting() == .standard)
  }

  @Test(arguments: RoomLighting.allCases)
  func everyLightingSurvivesTheStore(_ lighting: RoomLighting) throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveLighting(lighting)
    #expect(store.loadLighting() == lighting)
  }

  @Test func anUnknownOrBrokenLightingGivesTheStandardOne() throws {
    let storage = storage()
    let store = WidgetFeaturesStore(storage: storage)
    try storage.write(WidgetFeaturesStore.lightingFileName, Data(#""disco""#.utf8))
    #expect(store.loadLighting() == .standard)
    try storage.write(WidgetFeaturesStore.lightingFileName, Data("not json".utf8))
    #expect(store.loadLighting() == .standard)
  }

  @Test(arguments: RoomLighting.allCases)
  func everyLightingHasWords(_ lighting: RoomLighting) {
    #expect(!lighting.title.isEmpty)
    #expect(!lighting.detail.isEmpty)
  }

  @MainActor @Test func modelStartsFromTheStoreAndSavesAChoice() {
    let store = WidgetFeaturesStore(storage: storage())
    let model = WidgetFeaturesModel(store: store)
    #expect(model.lighting == .standard)
    model.setLighting(.candle)
    #expect(model.lighting == .candle)
    #expect(store.loadLighting() == .candle)
    #expect(WidgetFeaturesModel(store: store).lighting == .candle)
  }
}
