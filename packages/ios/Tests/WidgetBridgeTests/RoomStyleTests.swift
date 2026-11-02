import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct RoomStyleTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func windowSeatIsTheStandardStyleAndLeads() {
    #expect(RoomStyle.standard == .windowSeat)
    #expect(RoomStyle.allCases.first == .windowSeat)
  }

  @Test func nothingSavedGivesTheStandardStyle() {
    #expect(WidgetFeaturesStore(storage: storage()).loadRoomStyle() == .standard)
  }

  @Test(arguments: RoomStyle.allCases)
  func everyStyleSurvivesTheStore(_ style: RoomStyle) throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveRoomStyle(style)
    #expect(store.loadRoomStyle() == style)
  }

  @Test func anUnknownOrBrokenStyleGivesTheStandardOne() throws {
    let storage = storage()
    let store = WidgetFeaturesStore(storage: storage)
    try storage.write(WidgetFeaturesStore.roomStyleFileName, Data(#""attic""#.utf8))
    #expect(store.loadRoomStyle() == .standard)
    try storage.write(WidgetFeaturesStore.roomStyleFileName, Data("not json".utf8))
    #expect(store.loadRoomStyle() == .standard)
  }

  @Test func theStyleLeavesTheFlagsAlone() throws {
    let store = WidgetFeaturesStore(storage: storage())
    var features = WidgetFeatures()
    features.set(.streak, on: false)
    try store.save(features)
    try store.saveRoomStyle(.windowSeat)
    #expect(store.load() == features)
    #expect(store.loadRoomStyle() == .windowSeat)
  }

  @Test(arguments: RoomStyle.allCases)
  func everyStyleHasWords(_ style: RoomStyle) {
    #expect(!style.title.isEmpty)
    #expect(!style.detail.isEmpty)
  }

  @MainActor @Test func modelStartsFromTheStoreAndSavesAChoice() {
    let store = WidgetFeaturesStore(storage: storage())
    var changes = 0
    let model = WidgetFeaturesModel(store: store) { changes += 1 }
    #expect(model.roomStyle == .standard)
    model.setRoomStyle(.sunsetLamp)
    #expect(model.roomStyle == .sunsetLamp)
    #expect(store.loadRoomStyle() == .sunsetLamp)
    #expect(WidgetFeaturesModel(store: store).roomStyle == .sunsetLamp)
    // The widgets show nothing of the room, so they are not asked to redraw.
    #expect(changes == 0)
  }

  @MainActor @Test func modelWithoutAStoreStillSwitches() {
    let model = WidgetFeaturesModel(store: nil)
    model.setRoomStyle(.windowSeat)
    #expect(model.roomStyle == .windowSeat)
  }
}
