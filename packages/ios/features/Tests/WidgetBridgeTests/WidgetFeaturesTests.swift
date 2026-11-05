import Foundation
import Persistence
import Testing

@testable import WidgetBridge

@Suite struct WidgetFeaturesTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test(arguments: WidgetFeature.allCases)
  func everyFeatureStartsAtItsDefault(_ feature: WidgetFeature) {
    #expect(WidgetFeatures().isOn(feature) == feature.defaultOn)
  }

  @Test(arguments: WidgetFeature.allCases)
  func everyFeatureSwitchesOnItsOwn(_ feature: WidgetFeature) {
    var features = WidgetFeatures()
    features.set(feature, on: false)
    #expect(!features.isOn(feature))
    for other in WidgetFeature.allCases where other != feature {
      #expect(features.isOn(other) == other.defaultOn)
    }
    features.set(feature, on: true)
    #expect(features.isOn(feature))
  }

  @Test(arguments: WidgetFeature.allCases)
  func everyFeatureSurvivesTheStore(_ feature: WidgetFeature) throws {
    let store = WidgetFeaturesStore(storage: storage())
    var features = WidgetFeatures()
    features.set(feature, on: !feature.defaultOn)
    try store.save(features)
    #expect(store.load().isOn(feature) == !feature.defaultOn)
  }

  @Test func missingOrBrokenFileGivesDefaults() throws {
    let storage = storage()
    let store = WidgetFeaturesStore(storage: storage)
    #expect(store.load() == WidgetFeatures())
    try storage.write(WidgetFeaturesStore.fileName, Data("not json".utf8))
    #expect(store.load() == WidgetFeatures())
  }

  @Test func unknownStoredKeysAreIgnoredAndNewFeaturesKeepTheirDefault() throws {
    let storage = storage()
    try storage.write(
      WidgetFeaturesStore.fileName, Data(#"{"gone":false,"streak":false}"#.utf8))
    let loaded = WidgetFeaturesStore(storage: storage).load()
    #expect(!loaded.isOn(.streak))
    #expect(loaded.isOn(.timeOfDay) == WidgetFeature.timeOfDay.defaultOn)
  }

  @Test func aSavedCatMoodIsDroppedAndTheOtherChoicesStay() throws {
    let storage = storage()
    try storage.write(
      WidgetFeaturesStore.fileName,
      Data(#"{"catMood":true,"streak":false,"buttonPet":false}"#.utf8))
    let store = WidgetFeaturesStore(storage: storage)
    let loaded = store.load()
    #expect(!loaded.isOn(.streak))
    #expect(!loaded.isOn(.buttonPet))
    #expect(loaded.isOn(.timeOfDay))
    try store.save(loaded)
    let saved = try #require(try storage.read(WidgetFeaturesStore.fileName))
    #expect(!String(decoding: saved, as: UTF8.self).contains("catMood"))
  }

  @Test func aWidgetThatShowedOnlyTheCatMoodGoesBackToTheDefaultPictures() throws {
    var choices = ["catMood": true, "rotatePictures": false, "buttonHeart": false]
    for mode in PictureMode.allCases { choices[mode.feature.rawValue] = false }
    let storage = storage()
    try storage.write(WidgetFeaturesStore.fileName, try JSONEncoder().encode(choices))
    let loaded = WidgetFeaturesStore(storage: storage).load()
    for mode in PictureMode.allCases {
      #expect(loaded.isOn(mode.feature) == mode.feature.defaultOn, "\(mode)")
    }
    #expect(!loaded.isOn(.rotatePictures))
    #expect(!loaded.isOn(.buttonHeart))
    let inputs = PicturePlan.Inputs(
      features: loaded, snapshot: nil, hasDrawing: false, calendar: .current)
    #expect(PicturePlan.choice(inputs, at: .now) != .allOff)
  }

  @Test func aCatMoodThatWasOffLeavesTheOtherPicturesAsTheyWere() throws {
    var choices = ["catMood": false]
    for mode in PictureMode.allCases { choices[mode.feature.rawValue] = false }
    let storage = storage()
    try storage.write(WidgetFeaturesStore.fileName, try JSONEncoder().encode(choices))
    let loaded = WidgetFeaturesStore(storage: storage).load()
    #expect(PictureMode.allCases.allSatisfy { !loaded.isOn($0.feature) })
  }

  @Test func everyFeatureHasWordsAndAGroup() {
    for feature in WidgetFeature.allCases {
      #expect(!feature.title.isEmpty)
      #expect(!feature.detail.isEmpty)
      #expect(WidgetFeature.Group.allCases.contains(feature.group))
    }
  }

  @MainActor @Test func modelSavesAndAnnouncesOnlyRealChanges() {
    let store = WidgetFeaturesStore(storage: storage())
    var changes = 0
    let model = WidgetFeaturesModel(store: store) { changes += 1 }
    model.set(.streak, on: true)
    #expect(changes == 0)
    model.set(.streak, on: false)
    #expect(changes == 1)
    #expect(!model.isOn(.streak))
    #expect(!store.load().isOn(.streak))
  }
}
