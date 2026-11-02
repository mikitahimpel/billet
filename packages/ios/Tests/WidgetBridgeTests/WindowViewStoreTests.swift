import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct WindowViewStoreTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func nothingSavedGivesTheStandardView() {
    #expect(WidgetFeaturesStore(storage: storage()).loadWindowView() == .standard)
  }

  @Test func aBrokenFileGivesTheStandardView() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.windowViewFileName, Data("not json".utf8))
    #expect(WidgetFeaturesStore(storage: storage).loadWindowView() == .standard)
  }

  @MainActor @Test func modelStartsFromTheStoreAndSavesAChoice() {
    let store = WidgetFeaturesStore(storage: storage())
    var changes = 0
    let model = WidgetFeaturesModel(store: store) { changes += 1 }
    #expect(model.windowView == .standard)
    let choice = WindowViewChoice(view: .suburbNight, weather: .rain, hour: .dusk)
    model.setWindowView(choice)
    #expect(model.windowView == choice)
    #expect(store.loadWindowView() == choice)
    #expect(WidgetFeaturesModel(store: store).windowView == choice)
    // The widgets show nothing of the view, so they are not asked to redraw.
    #expect(changes == 0)
  }

  @Test func theViewLeavesTheRoomStyleAlone() throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveRoomStyle(.windowSeat)
    try store.saveWindowView(WindowViewChoice(view: .suburbNight, weather: .snow))
    #expect(store.loadRoomStyle() == .windowSeat)
  }
}
