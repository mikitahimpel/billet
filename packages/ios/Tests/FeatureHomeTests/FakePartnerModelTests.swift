import Delivery
import FeatureInbox
import Foundation
import Persistence
import Testing
import WidgetBridge

@testable import FeatureHome

@Suite("Fake partner in the app model")
@MainActor
struct FakePartnerModelTests {
  private let suite = "fake-model-\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)

  private var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

  private func makeModel(fakeOn: Bool = false) -> AppModel {
    let labs = WidgetFeaturesModel(
      store: WidgetFeaturesStore(storage: .directory(directory.appending(path: "labs"))))
    if fakeOn { labs.set(LabExperiment.fakePartner, on: true) }
    return AppModel(
      dependencies: AppModel.Dependencies(
        defaults: defaults,
        archive: NoteArchive(storage: .directory(directory.appending(path: "real"))),
        delivery: { _ in NoteDelivery.localFake },
        clearSurfaces: {},
        pairingTimeout: .seconds(60),
        labs: labs,
        fakeArchive: NoteArchive(storage: .directory(directory.appending(path: "fake")))))
  }

  @Test func theSwitchOnAtLaunchOpensHomeWithTheFakePartner() throws {
    let model = makeModel(fakeOn: true)
    let session = try #require(model.session)
    #expect(session.isFakePartner)
    #expect(model.isFakePartner)
    #expect(DemoRoom.saved(in: defaults) == nil)
  }

  @Test func theSwitchOffReturnsToPairing() {
    let model = makeModel(fakeOn: true)
    model.fakePartnerSwitched(on: false)
    #expect(model.session == nil)
    #expect(!model.isFakePartner)
  }

  @Test func aRealPairComesBackAfterTheFakePartnerLeaves() throws {
    _ = DemoRoom.pair(code: "ABCDEFGHJK", in: defaults)
    let model = makeModel()
    let real = try #require(model.session)
    model.fakePartnerSwitched(on: true)
    #expect(try #require(model.session).isFakePartner)
    #expect(model.session !== real)
    model.fakePartnerSwitched(on: false)
    #expect(model.session === real)
    #expect(DemoRoom.saved(in: defaults)?.code == "ABCDEFGHJK")
  }

  @Test func loggingOutOfTheFakePartnerOnlyLeavesIt() async throws {
    _ = DemoRoom.pair(code: "ABCDEFGHJK", in: defaults)
    let model = makeModel()
    model.fakePartnerSwitched(on: true)
    let message = await model.logOut()
    #expect(message == nil)
    #expect(!model.labs.isOn(LabExperiment.fakePartner))
    #expect(!(try #require(model.session)).isFakePartner)
    #expect(DemoRoom.saved(in: defaults)?.code == "ABCDEFGHJK")
  }

  @Test func withoutAFakeArchiveTheSwitchDoesNothing() {
    let labs = WidgetFeaturesModel(store: nil)
    labs.set(LabExperiment.fakePartner, on: true)
    let model = AppModel(
      dependencies: AppModel.Dependencies(
        defaults: defaults,
        archive: NoteArchive(storage: .directory(directory)),
        delivery: { _ in nil }, clearSurfaces: {}, pairingTimeout: .seconds(60), labs: labs))
    #expect(model.session == nil)
  }
}
