import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite @MainActor struct RemoteFlagsTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  private func model(_ storage: AppGroupStorage? = nil) -> (WidgetFeaturesModel, AppGroupStorage) {
    let storage = storage ?? self.storage()
    return (WidgetFeaturesModel(store: WidgetFeaturesStore(storage: storage)), storage)
  }

  private func flags(_ variant: String) -> RemoteFlags {
    RemoteFlags(assignments: [Experiments.roomLighting.key: variant])
  }

  // MARK: what the build contains

  @Test func experimentKeysAreUnique() {
    #expect(Set(Experiments.all.map(\.key)).count == Experiments.all.count)
  }

  // MARK: reading the server's answer

  @Test func aVariantTheBuildHasIsReturned() {
    #expect(flags("fairy-lights").variant(of: Experiments.roomLighting) == "fairy-lights")
  }

  @Test func aVariantTheBuildDoesNotHaveIsIgnored() {
    #expect(flags("disco").variant(of: Experiments.roomLighting) == nil)
  }

  @Test func anExperimentNotListedHasNoVariant() {
    #expect(RemoteFlags().variant(of: Experiments.roomLighting) == nil)
    #expect(
      RemoteFlags(assignments: ["other": "fairy-lights"]).variant(of: Experiments.roomLighting)
        == nil)
  }

  @Test func noMoreThanTheLimitIsKept() {
    let many = Dictionary(uniqueKeysWithValues: (0..<200).map { ("exp-\($0)", "v") })
    let kept = RemoteFlags(assignments: many)
    let data = try? JSONEncoder().encode(kept)
    let count = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0).count }
    #expect(count == RemoteFlags.limit)
  }

  // MARK: how the room is lit

  @Test func withNoAnswerTheLightIsWhatItAlwaysWas() {
    #expect(model().0.lighting == .standard)
  }

  @Test func theServersVariantChoosesTheLight() {
    let (model, _) = model()
    model.setRemote(flags("golden-hour"))
    #expect(model.lighting == .goldenHour)
    model.setRemote(flags("fairy-lights"))
    #expect(model.lighting == .fairyLights)
  }

  @Test func aLabsChoiceBeatsTheServer() {
    let (model, _) = model()
    model.setRemote(flags("golden-hour"))
    model.setLighting(.candle)
    #expect(model.lighting == .candle)
    #expect(model.lightingOverride == .candle)
  }

  @Test func followingTheTestReturnsToTheServersVariant() {
    let (model, _) = model()
    model.setRemote(flags("fairy-lights"))
    model.setLighting(.goldenHour)
    model.followTheLightingTest()
    #expect(model.lightingOverride == nil)
    #expect(model.lighting == .fairyLights)
  }

  @Test func aVariantTheBuildDoesNotHaveLeavesTheLightAlone() {
    let (model, _) = model()
    model.setRemote(flags("disco"))
    #expect(model.lighting == .standard)
  }

  @Test func anAnswerReplacesTheLastOneSoSwitchingATestOffTakesEffect() {
    let (model, _) = model()
    model.setRemote(flags("golden-hour"))
    model.setRemote(RemoteFlags())
    #expect(model.remote.isEmpty)
    #expect(model.lighting == .standard)
  }

  // MARK: offline and storage

  @Test func theLastAnswerSurvivesARestartForOfflineUse() {
    let (first, storage) = model()
    first.setRemote(flags("fairy-lights"))
    let (second, _) = model(storage)
    #expect(second.lighting == .fairyLights)
  }

  @Test func theLabsChoiceSurvivesARestartAndSoDoesFollowing() {
    let (first, storage) = model()
    first.setLighting(.goldenHour)
    #expect(model(storage).0.lightingOverride == .goldenHour)
    first.followTheLightingTest()
    #expect(model(storage).0.lightingOverride == nil)
  }

  @Test func anUnreadableFileGivesNoFlagsRatherThanACrash() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.remoteFlagsFileName, Data("not json".utf8))
    #expect(WidgetFeaturesStore(storage: storage).loadRemoteFlags().isEmpty)
    try storage.write(WidgetFeaturesStore.remoteFlagsFileName, Data(#"{"a":1}"#.utf8))
    #expect(WidgetFeaturesStore(storage: storage).loadRemoteFlags().isEmpty)
  }

  @Test func noStoreStillWorksInMemory() {
    let model = WidgetFeaturesModel(store: nil)
    model.setRemote(flags("fairy-lights"))
    #expect(model.lighting == .fairyLights)
  }

  @Test func theAnswerLeavesTheLabsFlagsAlone() throws {
    let (model, storage) = model()
    model.set(LabExperiment.lifeBubble, on: true)
    model.setRemote(flags("fairy-lights"))
    #expect(WidgetFeaturesStore(storage: storage).load().isOn(LabExperiment.lifeBubble))
  }

  @Test func theWidgetsAreToldWhenTheAnswerChangesAndNotWhenItDoesNot() {
    var told = 0
    let model = WidgetFeaturesModel(
      store: WidgetFeaturesStore(storage: storage()), onChange: { told += 1 })
    model.setRemote(flags("fairy-lights"))
    model.setRemote(flags("fairy-lights"))
    #expect(told == 1)
  }
}
