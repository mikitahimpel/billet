import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

/// The Labs settings the server can set: a choice on this phone beats the pair's variant, which
/// beats the standard value.
@Suite @MainActor struct RemoteSettingsTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  private func model(_ storage: AppGroupStorage? = nil) -> (WidgetFeaturesModel, AppGroupStorage) {
    let storage = storage ?? self.storage()
    return (WidgetFeaturesModel(store: WidgetFeaturesStore(storage: storage)), storage)
  }

  private func flags(_ assignments: [String: String]) -> RemoteFlags {
    RemoteFlags(assignments: assignments)
  }

  private let everything = [
    "room-lighting": "candle", "window-view": "fire-escape", "home-layout": "immersive",
    "shopkeeper": "human",
  ]

  // MARK: with nothing chosen and nothing from the server

  @Test func withNothingEverySettingIsStandard() {
    let (model, _) = model()
    #expect(model.lighting == .standard)
    #expect(model.windowView == .standard)
    #expect(model.homeVariant == .standard)
    #expect(model.shopkeeper == .standard)
    #expect(model.lightingOverride == nil)
    #expect(model.windowViewOverride == nil)
    #expect(model.homeVariantOverride == nil)
    #expect(model.shopkeeperOverride == nil)
  }

  // MARK: the server's variant

  @Test func theServersVariantBeatsTheStandardValue() {
    let (model, _) = model()
    model.setRemote(flags(everything))
    #expect(model.lighting == .candle)
    #expect(model.windowView == WindowViewChoice(view: .fireEscape))
    #expect(model.homeVariant == .immersive)
    #expect(model.shopkeeper == .human)
  }

  @Test func theServerSetsOnlyTheViewNotItsWeatherOrHour() {
    let (model, _) = model()
    model.setRemote(flags(["window-view": "rainy-suburb"]))
    #expect(model.windowView.weather == nil)
    #expect(model.windowView.hour == nil)
  }

  @Test func aVariantThisBuildLacksGivesTheStandardValue() {
    let (model, _) = model()
    model.setRemote(
      flags([
        "room-lighting": "disco", "window-view": "moon-base", "home-layout": "tabs",
        "shopkeeper": "owl",
      ]))
    #expect(model.lighting == .standard)
    #expect(model.windowView == .standard)
    #expect(model.homeVariant == .standard)
    #expect(model.shopkeeper == .standard)
  }

  @Test func switchingTheFlagOffGoesBackToTheStandardValue() {
    let (model, _) = model()
    model.setRemote(flags(everything))
    model.setRemote(RemoteFlags())
    #expect(model.lighting == .standard)
    #expect(model.windowView == .standard)
    #expect(model.homeVariant == .standard)
    #expect(model.shopkeeper == .standard)
  }

  // MARK: a choice in Labs

  @Test func aLabsChoiceBeatsTheServer() {
    let (model, _) = model()
    model.setRemote(flags(everything))
    let view = WindowViewChoice(view: .pinkDusk, weather: .fog)
    model.setLighting(.off)
    model.setWindowView(view)
    model.setHomeVariant(.livingWindow)
    model.setShopkeeper(.teddy)
    #expect(model.lighting == .off)
    #expect(model.windowView == view)
    #expect(model.homeVariant == .livingWindow)
    #expect(model.shopkeeper == .teddy)
    #expect(model.lightingOverride == .off)
    #expect(model.windowViewOverride == view)
    #expect(model.homeVariantOverride == .livingWindow)
    #expect(model.shopkeeperOverride == .teddy)
  }

  @Test func choosingTheStandardValueStillBeatsTheServer() {
    let (model, _) = model()
    model.setRemote(flags(everything))
    model.setLighting(.standard)
    model.setShopkeeper(.standard)
    #expect(model.lighting == .standard)
    #expect(model.shopkeeper == .standard)
  }

  @Test func followingTheTestShowsTheServersVariant() {
    let (model, _) = model()
    model.setRemote(flags(everything))
    model.setLighting(.off)
    model.setWindowView(WindowViewChoice(view: .pinkDusk, weather: .fog))
    model.setHomeVariant(.livingWindow)
    model.setShopkeeper(.teddy)
    model.followTheLightingTest()
    model.followTheWindowViewTest()
    model.followTheHomeVariantTest()
    model.followTheShopkeeperTest()
    #expect(model.lightingOverride == nil)
    #expect(model.windowViewOverride == nil)
    #expect(model.homeVariantOverride == nil)
    #expect(model.shopkeeperOverride == nil)
    #expect(model.lighting == .candle)
    #expect(model.windowView == WindowViewChoice(view: .fireEscape))
    #expect(model.homeVariant == .immersive)
    #expect(model.shopkeeper == .human)
  }

  @Test func followingTheTestWithNoTestGivesTheStandardValue() {
    let (model, _) = model()
    model.setLighting(.off)
    model.followTheLightingTest()
    #expect(model.lighting == .standard)
  }

  // MARK: storage

  @Test func theLabsChoicesSurviveANewModel() {
    let (first, storage) = model()
    let view = WindowViewChoice(view: .dormQuad, hour: .morning)
    first.setLighting(.goldenHour)
    first.setWindowView(view)
    first.setHomeVariant(.livingWindow)
    first.setShopkeeper(.teddy)
    let (second, _) = model(storage)
    second.setRemote(flags(everything))
    #expect(second.lightingOverride == .goldenHour)
    #expect(second.windowViewOverride == view)
    #expect(second.homeVariantOverride == .livingWindow)
    #expect(second.shopkeeperOverride == .teddy)
    #expect(second.lighting == .goldenHour)
    #expect(second.windowView == view)
    #expect(second.homeVariant == .livingWindow)
    #expect(second.shopkeeper == .teddy)
  }

  @Test func followingTheTestSurvivesANewModel() {
    let (first, storage) = model()
    first.setLighting(.goldenHour)
    first.setWindowView(WindowViewChoice(view: .dormQuad))
    first.setHomeVariant(.livingWindow)
    first.setShopkeeper(.teddy)
    first.followTheLightingTest()
    first.followTheWindowViewTest()
    first.followTheHomeVariantTest()
    first.followTheShopkeeperTest()
    let (second, _) = model(storage)
    #expect(second.lightingOverride == nil)
    #expect(second.windowViewOverride == nil)
    #expect(second.homeVariantOverride == nil)
    #expect(second.shopkeeperOverride == nil)
  }

  @Test func filesSavedBeforeTheServerCouldSetThemStillLoadAsChoices() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.lightingFileName, Data(#""neonNight""#.utf8))
    try storage.write(
      WidgetFeaturesStore.windowViewFileName,
      Data(#"{"view":"snowyDecember","weather":"snow","hour":"dusk"}"#.utf8))
    try storage.write(WidgetFeaturesStore.homeVariantFileName, Data(#""nightAndDay""#.utf8))
    try storage.write(WidgetFeaturesStore.shopkeeperFileName, Data(#""teddy""#.utf8))
    let (model, _) = model(storage)
    model.setRemote(flags(everything))
    #expect(model.lightingOverride == .neonNight)
    #expect(
      model.windowViewOverride
        == WindowViewChoice(view: .snowyDecember, weather: .snow, hour: .dusk))
    #expect(model.homeVariantOverride == .nightAndDay)
    #expect(model.shopkeeperOverride == .teddy)
    #expect(model.lighting == .neonNight)
  }

  @Test func anUnreadableFileIsNoChoice() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.lightingFileName, Data(#""disco""#.utf8))
    try storage.write(WidgetFeaturesStore.windowViewFileName, Data("not json".utf8))
    try storage.write(WidgetFeaturesStore.homeVariantFileName, Data("not json".utf8))
    try storage.write(WidgetFeaturesStore.shopkeeperFileName, Data(#""owl""#.utf8))
    let store = WidgetFeaturesStore(storage: storage)
    #expect(store.loadLightingOverride() == nil)
    #expect(store.loadWindowViewOverride() == nil)
    #expect(store.loadHomeVariantOverride() == nil)
    #expect(store.loadShopkeeperOverride() == nil)
  }

  @Test func clearingANeverSavedChoiceIsFine() throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.clearLighting()
    try store.clearWindowView()
    try store.clearHomeVariant()
    try store.clearShopkeeper()
    #expect(store.loadLightingOverride() == nil)
  }

  @Test func noStoreStillWorksInMemory() {
    let model = WidgetFeaturesModel(store: nil)
    model.setRemote(flags(everything))
    #expect(model.shopkeeper == .human)
    model.setShopkeeper(.teddy)
    #expect(model.shopkeeper == .teddy)
    model.followTheShopkeeperTest()
    #expect(model.shopkeeper == .human)
  }
}
