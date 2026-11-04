import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct RemovedScenesMigrationTests {
  private static let key = "petScene.selectedID"

  private let defaults: UserDefaults
  private let storage: AppGroupStorage
  private let store: WidgetFeaturesStore

  init() throws {
    let name = "RemovedScenesMigrationTests-\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: name))
    storage = .directory(FileManager.default.temporaryDirectory.appending(path: name))
    store = WidgetFeaturesStore(storage: storage)
  }

  private func migrate() {
    RemovedScenesMigration.run(
      defaults: defaults, choiceKey: Self.key, keptSceneID: "nooki", store: store)
  }

  private func saveRoomStyle(_ raw: String) throws {
    try storage.writeJSON(raw, named: WidgetFeaturesStore.roomStyleFileName)
  }

  private var savedRoomStyle: String? {
    (try? storage.readJSON(String.self, named: WidgetFeaturesStore.roomStyleFileName)) ?? nil
  }

  @Test(arguments: ["sunsetLamp", "nooki", "windowSeat"])
  func aRoomChosenInLabsIsForgotten(_ raw: String) throws {
    defaults.set("nooki", forKey: Self.key)
    try saveRoomStyle(raw)
    migrate()
    #expect(savedRoomStyle == nil)
    #expect(defaults.string(forKey: Self.key) == "nooki")
  }

  @Test(arguments: ["little-house", "rooftop"])
  func aFlatSceneBecomesTheKeptScene(_ id: String) throws {
    defaults.set(id, forKey: Self.key)
    try saveRoomStyle("sunsetLamp")
    migrate()
    #expect(savedRoomStyle == nil)
    #expect(defaults.string(forKey: Self.key) == "nooki")
  }

  @Test func noChoiceBecomesTheKeptScene() {
    migrate()
    #expect(defaults.string(forKey: Self.key) == "nooki")
  }

  @Test func runningAgainChangesNothing() throws {
    defaults.set("little-house", forKey: Self.key)
    migrate()
    migrate()
    #expect(savedRoomStyle == nil)
    #expect(defaults.string(forKey: Self.key) == "nooki")
  }

  @Test(arguments: HomeRoom.allCases)
  @MainActor func theRoomChosenInLabsIsKept(_ room: HomeRoom) throws {
    try store.saveHomeRoom(room)
    try saveRoomStyle("nooki")
    migrate()
    migrate()
    #expect(store.loadHomeRoom() == room)
    #expect(WidgetFeaturesModel(store: store).homeRoom == room)
  }

  @Test func anUnknownSceneIsLeftAlone() {
    defaults.set("garden", forKey: Self.key)
    migrate()
    #expect(defaults.string(forKey: Self.key) == "garden")
  }
}
