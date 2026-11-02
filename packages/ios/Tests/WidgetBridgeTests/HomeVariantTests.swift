import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@MainActor
@Suite struct HomeVariantTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func theStandardVariantIsTheHomeThereWasBefore() {
    #expect(HomeVariant.standard == .classic)
    #expect(!HomeVariant.classic.isFullBleed)
  }

  @Test func everyNewVariantFillsTheScreen() {
    for variant in HomeVariant.allCases where variant != .classic {
      #expect(variant.isFullBleed)
    }
  }

  @Test func nothingSavedGivesTheStandardVariant() {
    #expect(WidgetFeaturesStore(storage: storage()).loadHomeVariant() == .standard)
  }

  @Test(arguments: HomeVariant.allCases)
  func everyVariantSurvivesTheStore(_ variant: HomeVariant) throws {
    let store = WidgetFeaturesStore(storage: storage())
    try store.saveHomeVariant(variant)
    #expect(store.loadHomeVariant() == variant)
  }

  @Test func anUnknownOrBrokenVariantGivesTheStandardOne() throws {
    let storage = storage()
    let store = WidgetFeaturesStore(storage: storage)
    try storage.write(WidgetFeaturesStore.homeVariantFileName, Data(#""carousel""#.utf8))
    #expect(store.loadHomeVariant() == .standard)
    try storage.write(WidgetFeaturesStore.homeVariantFileName, Data("not json".utf8))
    #expect(store.loadHomeVariant() == .standard)
  }

  @Test func theModelSavesTheVariantWithoutTouchingTheFlagsOrTheRoom() {
    let storage = storage()
    var changes = 0
    let model = WidgetFeaturesModel(store: WidgetFeaturesStore(storage: storage)) { changes += 1 }
    model.setHomeVariant(.livingWindow)
    #expect(model.homeVariant == .livingWindow)
    #expect(model.roomStyle == .standard)
    #expect(changes == 0)
    let reopened = WidgetFeaturesModel(store: WidgetFeaturesStore(storage: storage))
    #expect(reopened.homeVariant == .livingWindow)
  }

  @Test func aPretendHourSurvivesTheStoreAndTheRealClockComesBack() throws {
    let store = WidgetFeaturesStore(storage: storage())
    #expect(store.loadPretendHour() == nil)
    try store.savePretendHour(23)
    #expect(store.loadPretendHour() == 23)
    try store.savePretendHour(nil)
    #expect(store.loadPretendHour() == nil)
  }

  @Test func anHourOutsideTheDayIsTheRealClock() {
    let model = WidgetFeaturesModel(store: WidgetFeaturesStore(storage: storage()))
    model.setPretendHour(24)
    #expect(model.pretendHour == nil)
    model.setPretendHour(5)
    #expect(model.pretendHour == 5)
  }
}
