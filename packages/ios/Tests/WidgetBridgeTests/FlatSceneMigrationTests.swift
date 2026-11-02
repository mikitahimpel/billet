import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct FlatSceneMigrationTests {
  private static let key = "petScene.selectedID"

  private let defaults: UserDefaults
  private let store: WidgetFeaturesStore

  init() throws {
    let name = "FlatSceneMigrationTests-\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: name))
    store = WidgetFeaturesStore(
      storage: .directory(FileManager.default.temporaryDirectory.appending(path: name)))
  }

  private func migrate() {
    FlatSceneMigration.run(
      defaults: defaults, choiceKey: Self.key, keptSceneID: "nooki", store: store)
  }

  @Test(arguments: ["little-house", "rooftop"])
  func aFlatSceneBecomesWindowSeat(_ id: String) throws {
    defaults.set(id, forKey: Self.key)
    try store.saveRoomStyle(.nooki)
    migrate()
    #expect(store.loadRoomStyleOverride() == nil)
    #expect(store.loadRoomStyle() == .windowSeat)
    #expect(defaults.string(forKey: Self.key) == "nooki")
  }

  @Test func noChoiceBecomesWindowSeat() {
    migrate()
    #expect(store.loadRoomStyle() == .windowSeat)
    #expect(defaults.string(forKey: Self.key) == "nooki")
  }

  @MainActor @Test func aFlatSceneFollowsThePairsTest() throws {
    defaults.set("little-house", forKey: Self.key)
    try store.saveRoomStyle(.nooki)
    try store.saveRemoteFlags(RemoteFlags(assignments: ["home-direction": "sunset-lamp"]))
    migrate()
    #expect(WidgetFeaturesModel(store: store).roomStyle == .sunsetLamp)
  }

  @Test func aNookiChoiceKeepsItsRoom() throws {
    defaults.set("nooki", forKey: Self.key)
    try store.saveRoomStyle(.sunsetLamp)
    migrate()
    #expect(store.loadRoomStyleOverride() == .sunsetLamp)
  }

  @Test func runningAgainKeepsALaterChoice() throws {
    defaults.set("little-house", forKey: Self.key)
    migrate()
    try store.saveRoomStyle(.nooki)
    migrate()
    #expect(store.loadRoomStyleOverride() == .nooki)
  }

  @Test func anUnknownSceneIsLeftAlone() throws {
    defaults.set("garden", forKey: Self.key)
    try store.saveRoomStyle(.nooki)
    migrate()
    #expect(store.loadRoomStyleOverride() == .nooki)
    #expect(defaults.string(forKey: Self.key) == "garden")
  }
}
