import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct RoomFurnitureTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func theStandardFurnitureIsTheCosyNook() {
    #expect(RoomFurniture.standard == .cosyNook)
  }

  @Test func nothingSavedGivesTheStandardFurniture() {
    #expect(WidgetFeaturesStore(storage: storage()).loadFurniture() == .standard)
  }

  @Test(arguments: RoomFurniture.allCases)
  func everyFurnitureSurvivesTheStore(_ furniture: RoomFurniture) throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveFurniture(furniture)
    #expect(store.loadFurniture() == furniture)
  }

  @Test func anUnknownOrBrokenFurnitureGivesTheStandardOne() throws {
    let storage = storage()
    let store = WidgetFeaturesStore(storage: storage)
    try storage.write(WidgetFeaturesStore.furnitureFileName, Data(#""throne""#.utf8))
    #expect(store.loadFurniture() == .standard)
    try storage.write(WidgetFeaturesStore.furnitureFileName, Data("not json".utf8))
    #expect(store.loadFurniture() == .standard)
  }

  @Test(arguments: RoomFurniture.allCases)
  func everyFurnitureHasWords(_ furniture: RoomFurniture) {
    #expect(!furniture.title.isEmpty)
    #expect(!furniture.detail.isEmpty)
  }

  @MainActor @Test func modelStartsFromTheStoreAndSavesAChoice() {
    let store = WidgetFeaturesStore(storage: storage())
    let model = WidgetFeaturesModel(store: store)
    #expect(model.furniture == .standard)
    model.setFurniture(.retroDen)
    #expect(model.furniture == .retroDen)
    #expect(store.loadFurniture() == .retroDen)
    #expect(WidgetFeaturesModel(store: store).furniture == .retroDen)
  }
}
