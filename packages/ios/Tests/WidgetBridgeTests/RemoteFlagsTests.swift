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
    RemoteFlags(assignments: [Experiments.homeDirection.key: variant])
  }

  // MARK: what the build contains

  @Test(arguments: Experiments.homeDirection.variants.sorted())
  func everyVariantOfHomeDirectionHasARoomToShow(_ variant: String) {
    #expect(RoomStyle(homeDirectionVariant: variant) != nil)
  }

  @Test func aVariantThisBuildDoesNotHaveHasNoRoom() {
    #expect(RoomStyle(homeDirectionVariant: "attic") == nil)
    #expect(RoomStyle(homeDirectionVariant: "") == nil)
  }

  @Test func experimentKeysAreUnique() {
    #expect(Set(Experiments.all.map(\.key)).count == Experiments.all.count)
  }

  // MARK: reading the server's answer

  @Test func aVariantTheBuildHasIsReturned() {
    #expect(flags("window-seat").variant(of: Experiments.homeDirection) == "window-seat")
  }

  @Test func aVariantTheBuildDoesNotHaveIsIgnored() {
    #expect(flags("attic").variant(of: Experiments.homeDirection) == nil)
  }

  @Test func anExperimentNotListedHasNoVariant() {
    #expect(RemoteFlags().variant(of: Experiments.homeDirection) == nil)
    #expect(
      RemoteFlags(assignments: ["other": "window-seat"]).variant(of: Experiments.homeDirection)
        == nil)
  }

  @Test func noMoreThanTheLimitIsKept() {
    let many = Dictionary(uniqueKeysWithValues: (0..<200).map { ("exp-\($0)", "v") })
    let kept = RemoteFlags(assignments: many)
    let data = try? JSONEncoder().encode(kept)
    let count = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0).count }
    #expect(count == RemoteFlags.limit)
  }

  // MARK: what the room shows

  @Test func withNoAnswerTheRoomIsWhatItAlwaysWas() {
    #expect(model().0.roomStyle == .standard)
  }

  @Test func theServersVariantChoosesTheRoom() {
    let (model, _) = model()
    model.setRemote(flags("sunset-lamp"))
    #expect(model.roomStyle == .sunsetLamp)
    model.setRemote(flags("window-seat"))
    #expect(model.roomStyle == .windowSeat)
  }

  @Test func aLabsChoiceBeatsTheServer() {
    let (model, _) = model()
    model.setRemote(flags("sunset-lamp"))
    model.setRoomStyle(.nooki)
    #expect(model.roomStyle == .nooki)
    #expect(model.roomStyleOverride == .nooki)
  }

  @Test func followingTheTestReturnsToTheServersVariant() {
    let (model, _) = model()
    model.setRemote(flags("window-seat"))
    model.setRoomStyle(.sunsetLamp)
    model.followTheTest()
    #expect(model.roomStyleOverride == nil)
    #expect(model.roomStyle == .windowSeat)
  }

  @Test func aVariantTheBuildDoesNotHaveLeavesTheRoomAlone() {
    let (model, _) = model()
    model.setRemote(flags("attic"))
    #expect(model.roomStyle == .standard)
  }

  @Test func anAnswerReplacesTheLastOneSoSwitchingATestOffTakesEffect() {
    let (model, _) = model()
    model.setRemote(flags("sunset-lamp"))
    model.setRemote(RemoteFlags())
    #expect(model.remote.isEmpty)
    #expect(model.roomStyle == .standard)
  }

  // MARK: offline and storage

  @Test func theLastAnswerSurvivesARestartForOfflineUse() {
    let (first, storage) = model()
    first.setRemote(flags("window-seat"))
    let (second, _) = model(storage)
    #expect(second.roomStyle == .windowSeat)
  }

  @Test func theLabsChoiceSurvivesARestartAndSoDoesFollowing() {
    let (first, storage) = model()
    first.setRoomStyle(.sunsetLamp)
    #expect(model(storage).0.roomStyleOverride == .sunsetLamp)
    first.followTheTest()
    #expect(model(storage).0.roomStyleOverride == nil)
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
    model.setRemote(flags("window-seat"))
    #expect(model.roomStyle == .windowSeat)
  }

  @Test func theAnswerLeavesTheLabsFlagsAlone() throws {
    let (model, storage) = model()
    model.set(LabExperiment.catPurrs, on: true)
    model.setRemote(flags("window-seat"))
    #expect(WidgetFeaturesStore(storage: storage).load().isOn(LabExperiment.catPurrs))
  }

  @Test func theWidgetsAreToldWhenTheAnswerChangesAndNotWhenItDoesNot() {
    var told = 0
    let model = WidgetFeaturesModel(
      store: WidgetFeaturesStore(storage: storage()), onChange: { told += 1 })
    model.setRemote(flags("window-seat"))
    model.setRemote(flags("window-seat"))
    #expect(told == 1)
  }
}
