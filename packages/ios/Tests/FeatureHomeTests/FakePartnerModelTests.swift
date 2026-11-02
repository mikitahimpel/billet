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

  private func fakeNotes(of model: AppModel, count: Int) async throws -> [NoteRecord] {
    let session = try #require(model.session)
    for _ in 0..<200 where session.notes.count < count {
      try await Task.sleep(for: .milliseconds(10))
    }
    return session.notes
  }

  @Test func aNewFakePartnerStartsWithALittleHistory() async throws {
    let notes = try await fakeNotes(of: makeModel(fakeOn: true), count: 2)
    #expect(notes.count == 2)
  }

  @Test func theFakePartnersNotesComeBackAfterARelaunch() async throws {
    let archive = NoteArchive(storage: .directory(directory.appending(path: "fake")))
    let first = makeModel(fakeOn: true)
    _ = try await fakeNotes(of: first, count: 2)
    _ = try await archive.add(NoteRecord(direction: .sent, date: .now, strokes: []))
    let notes = try await fakeNotes(of: makeModel(fakeOn: true), count: 3)
    #expect(notes.count == 3)
  }

  @Test func loggingOutOfTheFakePartnerDeletesItsNotes() async throws {
    let archive = NoteArchive(storage: .directory(directory.appending(path: "fake")))
    let model = makeModel(fakeOn: true)
    _ = try await fakeNotes(of: model, count: 2)
    _ = await model.logOut()
    #expect(try await archive.notes().isEmpty)
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
