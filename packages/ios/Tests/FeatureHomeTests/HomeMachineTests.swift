import BilletKit
import Delivery
import Foundation
import Ink
import Testing
import Wire

@testable import FeatureHome

@Suite("HomeMachine")
struct HomeMachineTests {
  private func apply(_ events: [HomeMachine.Event]) -> HomeMachine.State {
    events.reduce(HomeMachine.State()) { HomeMachine.transition($0, $1).0 }
  }

  private let strokes = [Stroke(color: "#000000", width: 2, points: [Point(x: 0.1, y: 0.1)])]

  @Test func startsAsleepOnHome() {
    let state = HomeMachine.State()
    #expect(state.screen == .home)
    #expect(state.cat == .sleeping)
    #expect(!state.noteArrived)
  }

  @Test func canvasOpensAndCloses() {
    #expect(apply([.canvasOpened]).screen == .canvas)
    #expect(apply([.canvasOpened, .canvasClosed]).screen == .home)
  }

  @Test func closingTheCanvasDoesNotWakeTheCat() {
    #expect(apply([.canvasOpened, .canvasClosed]).cat == .sleeping)
  }

  @Test func sendingReturnsHomeAndDeliversTheDrawing() {
    let (state, outputs) = HomeMachine.transition(
      apply([.canvasOpened]), .drawingSent(strokes))
    #expect(state.screen == .home)
    #expect(outputs == [.deliver(strokes)])
    #expect(!state.noteArrived)
  }

  @Test func arrivalSetsNoteArrivedAndHoldsTheDelivery() {
    let (state, outputs) = HomeMachine.transition(HomeMachine.State(), .noteArrived)
    #expect(state.noteArrived)
    #expect(outputs == [.holdDelivery])
  }

  @Test func playedDeliveryResetsNoteArrived() {
    let (state, outputs) = HomeMachine.transition(apply([.noteArrived]), .deliveryPlayed)
    #expect(!state.noteArrived)
    #expect(state.cat == .settling)
    #expect(outputs == [.holdSettling])
  }

  @Test func secondNotePlaysAgainAfterTheFirst() {
    let asleep = apply([.noteArrived, .deliveryPlayed, .settlingPlayed])
    #expect(asleep.cat == .sleeping)
    let (state, outputs) = HomeMachine.transition(asleep, .noteArrived)
    #expect(state.noteArrived)
    #expect(outputs == [.holdDelivery])
  }

  @Test func noteDuringDeliveryWaitsItsTurn() {
    let busy = apply([.noteArrived, .noteArrived])
    #expect(busy.waitingNotes == 1)
    let settling = HomeMachine.transition(busy, .deliveryPlayed).0
    #expect(!settling.noteArrived)
    let (state, outputs) = HomeMachine.transition(settling, .settlingPlayed)
    #expect(state.noteArrived)
    #expect(state.waitingNotes == 0)
    #expect(outputs == [.holdDelivery])
  }

  @Test func noteDuringSettlingWaitsItsTurn() {
    let state = apply([.noteArrived, .deliveryPlayed, .noteArrived])
    #expect(state.cat == .settling)
    #expect(!state.noteArrived)
    #expect(state.waitingNotes == 1)
  }

  @Test func lateHoldsAreIgnored() {
    #expect(apply([.deliveryPlayed, .settlingPlayed]) == HomeMachine.State())
    let delivering = apply([.noteArrived])
    #expect(HomeMachine.transition(delivering, .settlingPlayed).0 == delivering)
  }

  @Test @MainActor func storeRunsTheWholeDelivery() async {
    let store = Store<HomeMachine>(initial: HomeMachine.State()) {
      await HomeRunner.run($0, delivery: .localFake, sleep: { _ in })
    }
    store.send(.drawingSent(strokes))
    await store.settled()
    #expect(store.state == HomeMachine.State(cat: .sleeping))
  }

  @Test func receivedNoteWakesTheCatWithItsDrawing() {
    let (state, outputs) = HomeMachine.transition(HomeMachine.State(), .noteReceived(strokes))
    #expect(state.noteArrived)
    #expect(state.hungDrawing == strokes)
    #expect(state.inbox.isEmpty)
    #expect(outputs == [.holdDelivery])
  }

  @Test func notesHangInTheOrderTheyArrived() {
    let later = [Stroke(color: "#FFFFFF", width: 1, points: [Point(x: 0.2, y: 0.2)])]
    let busy = apply([.noteReceived(strokes), .noteReceived(later)])
    #expect(busy.hungDrawing == strokes)
    #expect(busy.waitingNotes == 1)
    let next = apply([
      .noteReceived(strokes), .noteReceived(later), .deliveryPlayed, .settlingPlayed,
    ])
    #expect(next.noteArrived)
    #expect(next.hungDrawing == later)
  }
}

@Suite("Demo delivery")
struct DemoDeliveryTests {
  private let strokes = [
    Stroke(color: "#112233", width: 0.01, points: [Point(x: 0.25, y: 0.5), Point(x: 0.75, y: 1.5)])
  ]

  @Test func inkSurvivesTheWire() throws {
    let decoded = try NoteInk.decode(NoteInk.encode(strokes))
    #expect(decoded.first?.color == "#112233")
    #expect(decoded.first?.points == strokes.first?.points)
  }

  @Test func garbledInkIsRejected() {
    #expect(throws: (any Error).self) { try NoteInk.decode("not base64!") }
  }

  @Test func generatedCodesAreValid() {
    #expect(DemoRoom.isValid(code: DemoRoom.generateCode()))
  }

  @Test func confusableCharactersAreNotValid() {
    #expect(!DemoRoom.isValid(code: "ABCDEFGHI0"))
    #expect(!DemoRoom.isValid(code: "ABCDEFGHJ"))
  }

  @Test func socketURLFollowsTheContract() {
    let room = DemoRoom(code: "ABCDEFGHJK", device: "d")
    #expect(
      room.socketURL(host: "example.test")?.absoluteString
        == "wss://example.test/demo/rooms/ABCDEFGHJK/socket?device=d")
  }

  @Test func deviceIDSurvivesChangingTheCode() throws {
    let defaults = try #require(UserDefaults(suiteName: "demo-room-tests"))
    defaults.removePersistentDomain(forName: "demo-room-tests")
    let first = DemoRoom.pair(code: "ABCDEFGHJK", in: defaults)
    DemoRoom.forget(in: defaults)
    #expect(DemoRoom.saved(in: defaults) == nil)
    let second = DemoRoom.pair(code: "ZYXWVTSRQP", in: defaults)
    #expect(second.device == first.device)
    #expect(DemoRoom.saved(in: defaults) == second)
  }

  @Test func pairingCarriesOverFromBeforeTheAppGroup() throws {
    let legacy = try #require(UserDefaults(suiteName: "demo-room-legacy"))
    let shared = try #require(UserDefaults(suiteName: "demo-room-shared"))
    legacy.removePersistentDomain(forName: "demo-room-legacy")
    shared.removePersistentDomain(forName: "demo-room-shared")
    let earlier = DemoRoom.pair(code: "ABCDEFGHJK", in: legacy)
    #expect(DemoRoom.saved(in: shared, legacy: legacy) == earlier)
    #expect(DemoRoom.saved(in: shared, legacy: shared) == earlier)
  }

  @Test func noteRequestAddsThisDevice() {
    let room = DemoRoom(code: "ABCDEFGHJK", device: "d")
    let url = room.noteRequestURL(noteURL: "https://example.test/demo/rooms/ABCDEFGHJK/notes/n")
    #expect(url?.absoluteString == "https://example.test/demo/rooms/ABCDEFGHJK/notes/n?device=d")
  }

  @Test func noteRequestRefusesOtherRoomsAndPlainHTTP() {
    let room = DemoRoom(code: "ABCDEFGHJK", device: "d")
    #expect(
      room.noteRequestURL(noteURL: "https://example.test/demo/rooms/ZZZZZZZZZZ/notes/n") == nil)
    #expect(
      room.noteRequestURL(noteURL: "http://example.test/demo/rooms/ABCDEFGHJK/notes/n") == nil)
    #expect(room.noteRequestURL(noteURL: "https://example.test/other") == nil)
  }

  @Test func pushedNoteIsFetchedAndSaved() async throws {
    let room = DemoRoom(code: "ABCDEFGHJK", device: "d")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubNoteRoute.self]
    let session = URLSession(configuration: configuration)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: file) }
    let base = "https://example.test/demo/rooms/ABCDEFGHJK/notes/"

    #expect(await room.saveNote(noteURL: base + "found", session: session, to: file))
    #expect(NoteImage.loadLatest(from: file) != nil)
    #expect(!(await room.saveNote(noteURL: base + "missing", session: session, to: file)))
  }

  @Test func noteBecomesAPNGFile() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("note.png")
    #expect(NoteImage.saveLatest(strokes, to: file))
    let data = try Data(contentsOf: file)
    #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(NoteImage.loadLatest(from: file) != nil)
  }

  @Test func fittedDrawingFillsTheSquare() throws {
    let points = try #require(NoteImage.fitted(strokes).first?.points)
    let span = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
    #expect(abs(span - 0.84) < 0.0001)
    #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
  }
}

/// Answers like the room's note route: this device's stored note, or 404.
private final class StubNoteRoute: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let client, let url = request.url else { return }
    let found = url.path.hasSuffix("found") && url.query == "device=d"
    let stroke = Stroke(
      color: "#000000", width: 0.01, points: [Point(x: 0, y: 0), Point(x: 1, y: 1)])
    let ink = (try? NoteInk.encode([stroke])) ?? ""
    let body = Data(#"{"id":"n","ink":"\#(ink)","from":"p"}"#.utf8)
    let response = HTTPURLResponse(
      url: url, statusCode: found ? 200 : 404, httpVersion: nil, headerFields: nil)
    if let response {
      client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    client.urlProtocol(self, didLoad: found ? body : Data())
    client.urlProtocolDidFinishLoading(self)
  }
}
