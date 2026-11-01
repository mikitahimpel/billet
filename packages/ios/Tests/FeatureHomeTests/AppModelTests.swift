import Delivery
import FeatureInbox
import Foundation
import Persistence
import Testing
import Wire

@testable import FeatureHome

/// A room connection the test drives by hand.
@MainActor
private final class FakeRoom {
  private(set) var continuation: AsyncStream<NoteDelivery.Update>.Continuation?
  private(set) var closed = 0
  private(set) var opened = 0
  private(set) var delivered: [[Stroke]] = []

  var delivery: NoteDelivery {
    NoteDelivery(
      deliver: { strokes in await MainActor.run { self.delivered.append(strokes) } },
      updates: {
        AsyncStream { continuation in
          MainActor.assumeIsolated {
            self.opened += 1
            self.continuation = continuation
          }
          continuation.onTermination = { _ in Task { @MainActor in self.closed += 1 } }
        }
      })
  }

  func emit(_ update: NoteDelivery.Update) async {
    continuation?.yield(update)
    try? await Task.sleep(for: .milliseconds(30))
  }
}

private actor Counter {
  private(set) var value = 0
  func increment() { value += 1 }
}

@Suite("AppModel")
@MainActor
struct AppModelTests {
  private let code = "ABCDEFGHJK"
  private let strokes = [Stroke(color: "#112233", width: 0.01, points: [Point(x: 0.2, y: 0.2)])]
  private let suite = "app-model-\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  private let room = FakeRoom()
  private let surfaces = Counter()

  private var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

  private func makeModel(
    storage: AppGroupStorage? = nil, timeout: Duration = .seconds(60)
  ) -> AppModel {
    let surfaces = surfaces
    return AppModel(
      dependencies: AppModel.Dependencies(
        defaults: defaults,
        archive: NoteArchive(storage: storage ?? .directory(directory)),
        delivery: { [room] _ in room.delivery },
        clearSurfaces: { await surfaces.increment() },
        pairingTimeout: timeout
      ))
  }

  private func paired() async throws -> (AppModel, PairSession) {
    let model = makeModel()
    model.join(code: code)
    let session = try #require(model.session)
    await room.emit(.status(.partnerHere))
    return (model, session)
  }

  private func isPaired(_ model: AppModel) -> Bool {
    if case .paired = model.stage { return true }
    return false
  }

  private func isUnpaired(_ model: AppModel) -> Bool {
    if case .unpaired = model.stage { return true }
    return false
  }

  @Test func firstLaunchIsUnpaired() {
    #expect(isUnpaired(makeModel()))
  }

  @Test func savedRoomOpensPaired() {
    _ = DemoRoom.pair(code: code, in: defaults)
    #expect(isPaired(makeModel()))
  }

  @Test func malformedCodeIsRefusedWithoutConnecting() {
    let model = makeModel()
    model.join(code: "ABC")
    #expect(model.failure == .invalidCode)
    #expect(room.opened == 0)
    #expect(DemoRoom.saved(in: defaults) == nil)
  }

  @Test func joiningWaitsForTheRoomThenEntersHome() async {
    let model = makeModel()
    model.join(code: code)
    #expect(!isPaired(model))
    await room.emit(.status(.connecting))
    #expect(!isPaired(model))
    await room.emit(.status(.partnerAway))
    #expect(isPaired(model))
  }

  @Test func aFullRoomReturnsToPairingWithAClearError() async {
    let model = makeModel()
    model.join(code: code)
    await room.emit(.status(.refused))
    #expect(isUnpaired(model))
    #expect(model.failure == .roomFull)
    #expect(DemoRoom.saved(in: defaults) == nil)
  }

  @Test func anUnreachableRoomGivesUp() async throws {
    let model = makeModel(timeout: .milliseconds(10))
    model.join(code: code)
    while model.failure == nil {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(model.failure == .unreachable)
    #expect(isUnpaired(model))
    #expect(DemoRoom.saved(in: defaults) == nil)
  }

  @Test func theCreatorStaysOnTheCodeUntilContinuing() async {
    let model = makeModel()
    model.createPair()
    await room.emit(.status(.partnerAway))
    #expect(!isPaired(model))
    model.finishCreating()
    #expect(isPaired(model))
  }

  @Test func theCreatorMovesOnWhenThePartnerJoins() async {
    let model = makeModel()
    model.createPair()
    await room.emit(.status(.partnerAway))
    await room.emit(.status(.partnerHere))
    #expect(isPaired(model))
  }

  @Test func aDroppedSocketReadsAsReconnecting() async throws {
    let (_, session) = try await paired()
    #expect(
      ConnectionLine(status: session.status, hasConnected: session.hasConnected) != .reconnecting)
    await room.emit(.status(.connecting))
    #expect(
      ConnectionLine(status: session.status, hasConnected: session.hasConnected) == .reconnecting)
  }

  @Test func firstConnectionIsNotAReconnect() {
    #expect(ConnectionLine(status: .connecting, hasConnected: false) == .connecting)
  }

  @Test func loadingStoredNotesKeepsOnesThatJustArrived() async throws {
    let old = NoteRecord(
      direction: .received, date: Date(timeIntervalSince1970: 1), strokes: strokes)
    try await NoteArchive(storage: .directory(directory)).add(old)
    let (_, session) = try await paired()
    session.send(strokes)
    await session.loadNotes()
    #expect(session.notes.map(\.direction) == [.sent, .received])
    #expect(session.notes.last == old)
  }

  @Test func sentAndReceivedNotesAreKept() async throws {
    let (_, session) = try await paired()
    session.send(strokes)
    await room.emit(.note(strokes))
    await session.savesFinished()
    #expect(session.notes.map(\.direction) == [.received, .sent])
    let stored = try await NoteArchive(storage: .directory(directory)).notes()
    #expect(stored.count == 2)
    #expect(stored.allSatisfy { $0.strokes == strokes })
  }

  @Test func logOutForgetsEverythingOnThisDevice() async throws {
    let (model, session) = try await paired()
    let device = session.room.device
    session.send(strokes)

    #expect(await model.logOut() == nil)

    #expect(isUnpaired(model))
    #expect(DemoRoom.saved(in: defaults) == nil)
    #expect(defaults.string(forKey: "demo.roomCode") == nil)
    #expect(defaults.string(forKey: "demo.deviceID") == nil)
    #expect(try AppGroupStorage.directory(directory).read(NoteArchive.fileName) == nil)
    #expect(await surfaces.value == 1)
    #expect(DemoRoom.pair(code: code, in: defaults).device != device)
  }

  @Test func logOutClosesTheSocket() async throws {
    let (model, _) = try await paired()
    #expect(room.closed == 0)
    _ = await model.logOut()
    try await Task.sleep(for: .milliseconds(30))
    #expect(room.closed == 1)
  }

  @Test func aNoteAfterLogOutIsNotKept() async throws {
    let (model, session) = try await paired()
    let continuation = room.continuation
    _ = await model.logOut()
    continuation?.yield(.note(strokes))
    try await Task.sleep(for: .milliseconds(30))
    await session.savesFinished()
    #expect(session.notes.isEmpty)
    #expect(try AppGroupStorage.directory(directory).read(NoteArchive.fileName) == nil)
  }

  @Test func aFailedEraseStaysPairedAndReconnects() async throws {
    let healthy = AppGroupStorage.directory(directory)
    let failing = AppGroupStorage(
      read: healthy.read,
      write: healthy.write,
      remove: { _ throws(PersistenceError) in throw .storage("disk") }
    )
    let model = makeModel(storage: failing)
    model.join(code: code)
    await room.emit(.status(.partnerHere))

    #expect(await model.logOut() != nil)

    #expect(isPaired(model))
    #expect(DemoRoom.saved(in: defaults) != nil)
    #expect(await surfaces.value == 0)
    #expect(room.opened == 2)
  }

  @Test func leavingAFullRoomKeepsTheDeviceID() async throws {
    let (model, session) = try await paired()
    model.changeCode()
    #expect(isUnpaired(model))
    #expect(defaults.string(forKey: "demo.deviceID") == session.room.device)
  }
}
