import Delivery
import DesignSystem
import FeatureInbox
import Foundation
import Observation
import Persistence
import Pet
import Testing
import WidgetBridge
import Wire

@testable import FeatureHome

/// A room connection the test drives by hand.
///
/// The session reads updates through an `AsyncStream(unfolding:)`, which asks for the next update
/// only after it has finished applying the previous one. `emit` returns on that ask, so it
/// returns when the session has handled the update, with no pause to guess at. `waitFor` waits
/// for what the session does in reply (the calls it makes on the room) by being woken each time
/// one is recorded.
@MainActor
private final class FakeRoom {
  private(set) var closed = 0 { didSet { changed() } }
  private(set) var opened = 0
  private(set) var delivered: [[Stroke]] = [] { didSet { changed() } }
  private(set) var deliveredIDs: [UUID] = [] { didSet { changed() } }
  private(set) var names: [String] = [] { didSet { changed() } }
  private(set) var plays: [PlayKind] = [] { didSet { changed() } }
  /// The life events sent, of every kind.
  private(set) var lived: [LifeEvent.Kind] = [] { didSet { changed() } }
  private(set) var reacted: [(UUID, Reaction)] = [] { didSet { changed() } }

  /// The connection the session holds now, by the number `updates` gave it.
  private var current: Int?
  private var queue: [NoteDelivery.Update] = []
  private var parked: CheckedContinuation<NoteDelivery.Update?, Never>?
  /// An update has been handed over and the session has not asked for the next one yet.
  private var inFlight = false
  private var appliedWaiters: [CheckedContinuation<Void, Never>] = []
  private var checks:
    [UUID: (predicate: () -> Bool, continuation: CheckedContinuation<Void, Never>)] =
      [:]

  var delivery: NoteDelivery {
    NoteDelivery(
      deliver: { strokes, id in
        await MainActor.run {
          self.delivered.append(strokes)
          self.deliveredIDs.append(id)
        }
      },
      play: { kind, _ in await MainActor.run { self.plays.append(kind) } },
      life: { event in
        await MainActor.run {
          self.lived.append(event.kind)
          if let kind = event.kind.playKind, kind == .pet { self.plays.append(kind) }
        }
      },
      nameCat: { name in await MainActor.run { self.names.append(name) } },
      react: { note, reaction in await MainActor.run { self.reacted.append((note, reaction)) } },
      updates: {
        let id = MainActor.assumeIsolated { self.attach() }
        return AsyncStream(
          unfolding: { await self.next(for: id) },
          onCancel: { Task { @MainActor in self.cancelled(id) } })
      })
  }

  private func attach() -> Int {
    opened += 1
    current = opened
    queue = []
    return opened
  }

  private func next(for id: Int) async -> NoteDelivery.Update? {
    guard current == id else { return nil }
    if inFlight {
      inFlight = false
      resumeApplied()
    }
    if !queue.isEmpty {
      inFlight = true
      return queue.removeFirst()
    }
    return await withCheckedContinuation { parked = $0 }
  }

  private func cancelled(_ id: Int) {
    if current == id {
      current = nil
      queue = []
      inFlight = false
      parked?.resume(returning: nil)
      parked = nil
      resumeApplied()
    }
    closed += 1
  }

  private func resumeApplied() {
    let waiters = appliedWaiters
    appliedWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  /// Sends `update` to the session and returns once the session has applied it. Nothing happens
  /// when no connection is open.
  func emit(_ update: NoteDelivery.Update) async {
    guard current != nil else { return }
    if let parked {
      self.parked = nil
      inFlight = true
      parked.resume(returning: update)
    } else {
      queue.append(update)
    }
    await withCheckedContinuation { continuation in
      appliedWaiters.append(continuation)
      Task { @MainActor in
        try? await Task.sleep(for: Self.hangLimit)
        if !appliedWaiters.isEmpty {
          Issue.record("the session did not finish applying \(update)")
          resumeApplied()
        }
      }
    }
  }

  /// Only so a broken test fails instead of hanging; a passing test never waits this long.
  private static let hangLimit = Duration.seconds(20)

  private func changed() {
    for (id, check) in checks where check.predicate() {
      checks[id] = nil
      check.continuation.resume()
    }
  }

  /// Returns once `predicate` holds, checking each time the room records something.
  func waitFor(_ what: String, _ predicate: @escaping () -> Bool) async {
    guard !predicate() else { return }
    let id = UUID()
    await withCheckedContinuation { continuation in
      checks[id] = (predicate, continuation)
      Task { @MainActor in
        try? await Task.sleep(for: Self.hangLimit)
        if let check = checks.removeValue(forKey: id) {
          Issue.record("timed out waiting for \(what)")
          check.continuation.resume()
        }
      }
    }
  }
}

/// Returns once `condition`, which reads observable state, holds; woken by each change to it.
@MainActor
private func waitUntil(_ what: String, _ condition: @escaping @MainActor () -> Bool) async {
  final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
      let first = lock.withLock {
        defer { done = true }
        return !done
      }
      if first { body() }
    }
  }
  let limit = ContinuousClock.now.advanced(by: .seconds(20))
  while !condition() {
    guard ContinuousClock.now < limit else {
      Issue.record("timed out waiting for \(what)")
      return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let once = Once()
      withObservationTracking {
        _ = condition()
      } onChange: {
        once.run { continuation.resume() }
      }
      Task {
        try? await Task.sleep(until: limit)
        once.run { continuation.resume() }
      }
    }
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

  @Test func partnerPresenceReachesThePetWorld() async throws {
    let (_, session) = try await paired()
    #expect(session.store.state.pet.world.partnerHere)
    await room.emit(.status(.partnerAway))
    #expect(!session.store.state.pet.world.partnerHere)
    await room.emit(.status(.connecting))
    #expect(!session.store.state.pet.world.partnerHere)
  }

  @Test func theRoomsCatNameShowsAndAnEmptyOneIsNotSent() async throws {
    let (_, session) = try await paired()
    session.nameCat("   ")
    #expect(session.play.catName == nil)
    #expect(room.names.isEmpty)
    session.nameCat(" Mochi ")
    #expect(session.play.catName == "Mochi")
    await room.emit(.catName("Biscuit"))
    #expect(session.play.catName == "Biscuit")
    await room.waitFor("the name") { room.names.count == 1 }
    #expect(room.names == ["Mochi"])
  }

  @Test func reactingToAReceivedNoteSendsItOnce() async throws {
    let (_, session) = try await paired()
    let id = UUID()
    await room.emit(.note(strokes, id: id))
    let received = try #require(session.notes.first)
    #expect(received.id == id)
    session.react(to: received, .heart)
    await room.waitFor("the reaction") { room.reacted.count == 1 }
    #expect(room.reacted.map(\.0) == [id])
    #expect(room.reacted.map(\.1) == [.heart])
    #expect(session.play.reactions[id] == .heart)
  }

  private func action(
    _ kind: WidgetActionKind, day: String? = nil, note: UUID? = nil
  ) -> WidgetAction {
    WidgetAction(
      kind: kind, at: .now, day: day ?? TreatDay.key(for: .now, calendar: .current), note: note)
  }

  @Test func widgetActionsGoThroughTheAppsOwnPaths() async throws {
    let (_, session) = try await paired()
    let id = UUID()
    await room.emit(.note(strokes, id: id))
    #expect(session.perform(action(.pet), now: .now) == .done)
    #expect(session.perform(action(.treat), now: .now) == .done)
    #expect(session.perform(action(.heart, note: id), now: .now) == .done)
    await room.waitFor("the plays and the reaction") {
      room.plays.count == 2 && room.reacted.count == 1
    }
    #expect(Set(room.plays) == [.pet, .treat])
    #expect(room.plays.count == 2)
    // The pet and the treat are both part of the cat's life too.
    await room.waitFor("the life events") { room.lived.count == 2 }
    #expect(Set(room.lived) == [.pet, .feed])
    let mine = session.life.log.all.filter { $0.by == session.room.device }.suffix(2)
    #expect(Set(mine.map(\.kind)) == [.pet, .feed])
    #expect(room.reacted.map(\.0) == [id])
    #expect(session.play.petsGiven == 1)
  }

  @Test func widgetActionsWaitForTheRoomAndNeverFakeASend() async throws {
    let model = makeModel()
    model.join(code: code)
    let session = try #require(model.session)
    #expect(session.status == .connecting)
    #expect(session.perform(action(.pet), now: .now) == .keep)
    #expect(session.perform(action(.treat), now: .now) == .keep)
    #expect(session.perform(action(.heart, note: UUID()), now: .now) == .keep)
    #expect(session.play.petsGiven == 0)
    #expect(session.perform(action(.openCanvas), now: .now) == .done)
    #expect(session.store.state.screen == .canvas)

    // Once the room answers, the same action goes through, and only that one reaches the room:
    // the three refused above were never sent.
    await room.emit(.status(.partnerHere))
    #expect(session.perform(action(.pet), now: .now) == .done)
    await room.waitFor("the pet") { room.plays.count == 1 }
    #expect(room.plays == [.pet])
    #expect(room.reacted.isEmpty)
  }

  @Test func staleOrRepeatedWidgetActionsAreDropped() async throws {
    let (_, session) = try await paired()
    #expect(session.perform(action(.treat, day: "2000-01-01"), now: .now) == .drop)
    #expect(session.perform(action(.heart), now: .now) == .drop)
    let today = TreatDay.key(for: .now, calendar: .current)
    session.giveTreat(on: today)
    #expect(session.perform(action(.treat), now: .now) == .drop)
  }

  @Test func drainingRemovesWhatItDidAndLeavesWhatItCouldNot() async throws {
    let queue = ActionQueue(
      directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let (_, session) = try await paired()
    try queue.enqueue(action(.pet))
    try queue.enqueue(action(.heart, note: UUID()))
    try queue.enqueue(action(.openCanvas))
    #expect(session.drain(queue))
    #expect(queue.pending(at: .now).map(\.kind) == [.heart])
  }

  @Test func aSentNoteCannotBeReactedTo() async throws {
    let (_, session) = try await paired()
    session.send(strokes)
    let sent = try #require(session.notes.first)
    session.react(to: sent, .heart)
    #expect(session.play.reactions.isEmpty)

    // A reaction to a received note goes out, and it is the only one that does.
    let received = UUID()
    await room.emit(.note(strokes, id: received))
    session.react(to: try #require(session.notes.first { $0.id == received }), .heart)
    await room.waitFor("the reaction") { room.reacted.count == 1 }
    #expect(room.reacted.map(\.0) == [received])
  }

  @Test func theSentNoteKeepsTheIDTheRoomWasGiven() async throws {
    let (_, session) = try await paired()
    session.send(strokes)
    await room.waitFor("the note") { room.deliveredIDs.count == 1 }
    #expect(room.deliveredIDs == [try #require(session.notes.first).id])
  }

  @Test func aPartnerReactionToMyNoteAnimatesOnceAndReplaysDoNot() async throws {
    let (_, session) = try await paired()
    session.send(strokes)
    let id = try #require(session.notes.first).id
    await room.emit(.reactions([id: .stamp]))
    #expect(session.reactionsSeen == 1)
    #expect(session.lastReaction == .stamp)
    await room.emit(.reactions([id: .stamp]))
    #expect(session.reactionsSeen == 1)
    await room.emit(.reactions([id: .heart, UUID(): .heart]))
    #expect(session.reactionsSeen == 2)
    #expect(session.lastReaction == .heart)
  }

  @Test func reactionsBeforeTheFirstRoomFrameShowWithoutAnimation() async throws {
    let model = makeModel()
    model.join(code: code)
    let session = try #require(model.session)
    let id = UUID()
    session.send(strokes)
    let sentID = try #require(session.notes.first).id
    await room.emit(.reactions([sentID: .heart, id: .heart]))
    #expect(session.play.reactions[sentID] == .heart)
    #expect(session.reactionsSeen == 0)
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
    await waitUntil("the pairing to give up") { model.failure != nil }
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

  @Test func aDropWaitsBeforeItIsNamedAndSaysSo() {
    #expect(ConnectionLine.reconnecting.text == "Reconnecting…")
    #expect(ConnectionLine.reconnecting.waitsBeforeShowing)
    #expect(ConnectionLine.connecting.waitsBeforeShowing)
    #expect(!ConnectionLine.refused.waitsBeforeShowing)
    #expect(!ConnectionLine.partnerHere.waitsBeforeShowing)
    #expect(ConnectionLine.patience == .seconds(3))
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
    await room.emit(.note(strokes, id: UUID()))
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
    await room.waitFor("the socket to close") { room.closed == 1 }
    #expect(room.closed == 1)
  }

  @Test func aNoteAfterLogOutIsNotKept() async throws {
    let (model, session) = try await paired()
    _ = await model.logOut()
    await room.emit(.note(strokes, id: UUID()))
    await room.waitFor("the socket to close") { room.closed == 1 }
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
