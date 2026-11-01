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
    #expect(loaded.isOn(.catMood) == WidgetFeature.catMood.defaultOn)
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
    model.set(.catMood, on: true)
    #expect(changes == 0)
    model.set(.catMood, on: false)
    #expect(changes == 1)
    #expect(!model.isOn(.catMood))
    #expect(!store.load().isOn(.catMood))
  }
}
