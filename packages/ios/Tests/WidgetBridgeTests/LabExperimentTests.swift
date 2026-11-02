import Foundation
import Persistence
import Testing

@testable import WidgetBridge

@Suite struct LabExperimentTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func withTheHomeCardsOffNoExperimentAddsACard() {
    var features = WidgetFeatures()
    for experiment in LabExperiment.allCases where experiment.hasHomeCard {
      features.set(experiment, on: false)
    }
    #expect(!LabExperiment.allCases.contains { $0.hasHomeCard && features.isOn($0) })
  }

  @Test func theCatsNeedsStartOnShownInTheRoomWithTheOtherWaysOff() {
    let features = WidgetFeatures()
    #expect(features.isOn(LabExperiment.catLife))
    #expect(features.isOn(LabExperiment.lifeInRoom))
    for other in [LabExperiment.lifeBubble, .lifeRings, .lifeChips, .lifeDebug] {
      #expect(!features.isOn(other))
    }
  }

  @Test(arguments: LabExperiment.allCases)
  func everyExperimentHasWordsAndAGroup(_ experiment: LabExperiment) {
    #expect(!experiment.title.isEmpty)
    #expect(!experiment.detail.isEmpty)
    #expect(LabExperiment.Group.allCases.contains(experiment.group))
  }

  @Test(arguments: LabExperiment.allCases)
  func everyExperimentSwitchesOnItsOwnAndSurvivesTheStore(_ experiment: LabExperiment) throws {
    let store = WidgetFeaturesStore(storage: storage())
    var features = WidgetFeatures()
    #expect(features.isOn(experiment) == experiment.defaultOn)
    features.set(experiment, on: !experiment.defaultOn)
    try store.save(features)
    let loaded = store.load()
    #expect(loaded.isOn(experiment) == !experiment.defaultOn)
    for other in LabExperiment.allCases where other != experiment {
      #expect(loaded.isOn(other) == other.defaultOn)
    }
    for widget in WidgetFeature.allCases {
      #expect(loaded.isOn(widget) == widget.defaultOn)
    }
  }

  @Test func widgetAndLabKeysNeverClash() {
    let widgetKeys = Set(WidgetFeature.allCases.map(\.rawValue))
    let labKeys = Set(LabExperiment.allCases.map(\.rawValue))
    #expect(widgetKeys.isDisjoint(with: labKeys))
  }

  @Test func theFakePartnerStartsOff() {
    #expect(!WidgetFeatures().isOn(LabExperiment.fakePartner))
  }

  @MainActor @Test func oneModelHoldsBothKinds() {
    let store = WidgetFeaturesStore(storage: storage())
    let model = WidgetFeaturesModel(store: store)
    model.set(LabExperiment.fakePartner, on: true)
    model.set(WidgetFeature.streak, on: false)
    let reloaded = WidgetFeaturesModel(store: store)
    #expect(reloaded.isOn(LabExperiment.fakePartner))
    #expect(!reloaded.isOn(WidgetFeature.streak))
  }
}
