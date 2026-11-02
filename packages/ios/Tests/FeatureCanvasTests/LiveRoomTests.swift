import Foundation
import Testing
import Transport
import Wire

@testable import FeatureCanvas

@Suite struct LiveRoomMachineTests {
  typealias M = LiveRoomMachine

  static let stroke = Stroke(color: "#A5442B", width: 0.03, points: [Point(x: 0.1, y: 0.1)])
  static func note(_ id: String) -> Note {
    .photo(id: NoteId(id), author: UserId("them"), sentAt: 1, image: MediaKey("k"))
  }

  static let online = M.State(isOnline: true)

  @Test func partnerStrokesAccumulateAndShowPresence() {
    var (state, _) = M.transition(Self.online, .received(.stroke(seq: 3, stroke: Self.stroke)))
    (state, _) = M.transition(state, .received(.stroke(seq: 3, stroke: Self.stroke)))
    #expect(state.strokes.count == 2)
    #expect(state.partner == .drawing)
  }

  @Test func theLiveDrawingIsBounded() {
    var state = Self.online
    for _ in 0..<(M.strokeLimit + 20) {
      (state, _) = M.transition(state, .received(.stroke(seq: 1, stroke: Self.stroke)))
    }
    #expect(state.strokes.count == M.strokeLimit)
  }

  @Test func presenceIdleDropsAnAbandonedDrawing() {
    var (state, _) = M.transition(Self.online, .received(.stroke(seq: 1, stroke: Self.stroke)))
    (state, _) = M.transition(state, .received(.presence(.idle)))
    #expect(state.strokes.isEmpty)
    #expect(state.partner == .idle)
  }

  @Test func aNoteArrivesOnceAndEndsTheLiveDrawing() {
    var (state, _) = M.transition(Self.online, .received(.stroke(seq: 1, stroke: Self.stroke)))
    var outputs: [M.Output]
    (state, outputs) = M.transition(state, .received(.noteReceived(seq: 4, note: Self.note("a"))))
    #expect(outputs == [.noteArrived(seq: 4, Self.note("a"))])
    #expect(state.strokes.isEmpty)
    #expect(state.lastNoteSeq == 4)

    // The same note again after a reconnect, and an older one, change nothing.
    for seq in [4, 3] {
      (state, outputs) = M.transition(
        state, .received(.noteReceived(seq: seq, note: Self.note("a"))))
      #expect(outputs.isEmpty)
    }
  }

  @Test func aDropForgetsTheLiveDrawingAndThePartnersPresence() {
    var (state, _) = M.transition(Self.online, .received(.stroke(seq: 1, stroke: Self.stroke)))
    (state, _) = M.transition(state, .linkChanged(online: false))
    #expect(state.strokes.isEmpty)
    #expect(state.partner == nil)
    #expect(!state.isOnline)
  }

  @Test func nothingIsSentOffline() {
    #expect(M.transition(M.State(), .strokeDrawn(Self.stroke)).1.isEmpty)
    #expect(M.transition(M.State(), .presenceChanged(.drawing)).1.isEmpty)
  }

  @Test func onlineStrokesAndPresenceAreSent() {
    #expect(
      M.transition(Self.online, .strokeDrawn(Self.stroke)).1 == [.send(.stroke(Self.stroke))])
    #expect(
      M.transition(Self.online, .presenceChanged(.drawing)).1 == [.send(.presence(.drawing))])
  }

  @Test func messagesBeforeTheLinkIsUpAreIgnored() {
    let (state, _) = M.transition(M.State(), .received(.stroke(seq: 1, stroke: Self.stroke)))
    #expect(state.strokes.isEmpty)
  }

  @Test func theBadgeTextFollowsPresence() {
    #expect(M.State(isOnline: false, partner: .drawing).presenceText == nil)
    #expect(M.State(isOnline: true, partner: nil).presenceText == nil)
    #expect(M.State(isOnline: true, partner: .idle).presenceText == "Your partner is here")
    #expect(M.State(isOnline: true, partner: .drawing).presenceText == "Your partner is drawing…")
  }
}

/// A socket the test drives: `incoming` is what the server sends, `sent` what the room wrote.
final class FakeSocket: Sendable {
  let incoming: AsyncStream<ServerMessage>.Continuation
  let sent: AsyncStream<ClientMessage>
  let connection: WebSocketConnection

  init() {
    let (messages, incoming) = AsyncStream.makeStream(of: ServerMessage.self)
    let (sent, sentContinuation) = AsyncStream.makeStream(of: ClientMessage.self)
    self.incoming = incoming
    self.sent = sent
    connection = WebSocketConnection(
      messages: messages,
      send: { (message) async throws(TransportError) in sentContinuation.yield(message) },
      close: { incoming.finish() })
  }
}

actor SocketQueue {
  private var sockets: [FakeSocket]
  init(_ sockets: [FakeSocket]) { self.sockets = sockets }
  func next() -> FakeSocket? { sockets.isEmpty ? nil : sockets.removeFirst() }
}

final class NoteLog: @unchecked Sendable {
  private let lock = NSLock()
  private var seqs: [Int] = []
  var values: [Int] { lock.withLock { seqs } }
  func add(_ seq: Int) { lock.withLock { seqs.append(seq) } }
}

@Suite @MainActor struct LiveRoomTests {
  static func room(
    sockets: [FakeSocket], lastSeq: Int? = nil, log: NoteLog = NoteLog()
  ) -> LiveRoom {
    let queue = SocketQueue(sockets)
    return LiveRoom(
      makeDependencies: { deliver in
        WebSocketDependencies(
          open: { () async throws(TransportError) -> WebSocketConnection in
            guard let socket = await queue.next() else { throw .network("none left") }
            return socket.connection
          },
          sleep: { duration in
            // Nothing times out and nothing waits to retry in a test.
            if duration >= WebSocketMachine.connectTimeout {
              try? await Task.sleep(for: .seconds(3600))
            }
          },
          deliver: deliver, jitter: { 1 })
      },
      lastSeq: lastSeq, onNote: { seq, _ in log.add(seq) })
  }

  static func wait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<2000 where !condition() { await Task.yield() }
  }

  @Test func partnerStrokesAndPresenceReachTheScreen() async {
    let socket = FakeSocket()
    let room = Self.room(sockets: [socket])
    room.connect()
    var sent = socket.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 0))

    socket.incoming.yield(.presence(.idle))
    await Self.wait { room.state.partner == .idle }
    socket.incoming.yield(.stroke(seq: 0, stroke: LiveRoomMachineTests.stroke))
    await Self.wait { room.state.strokes.count == 1 }
    #expect(room.state.partner == .drawing)

    room.disconnect()
  }

  @Test func ownPresenceAndStrokesAreSentOnceOnline() async {
    let socket = FakeSocket()
    let room = Self.room(sockets: [socket])
    room.setDrawing(true)  // offline: nothing is sent
    room.connect()
    var sent = socket.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 0))
    await Self.wait { room.isOnline }
    room.setDrawing(true)
    room.send(LiveRoomMachineTests.stroke)
    #expect(await sent.next() == .presence(.drawing))
    #expect(await sent.next() == .stroke(LiveRoomMachineTests.stroke))
    room.disconnect()
  }

  @Test func reconnectResumesAfterTheLastNoteAndShowsNoNoteTwice() async {
    let first = FakeSocket()
    let second = FakeSocket()
    let log = NoteLog()
    let room = Self.room(sockets: [first, second], log: log)
    room.connect()
    var firstSent = first.sent.makeAsyncIterator()
    #expect(await firstSent.next() == .resume(lastSeq: 0))

    first.incoming.yield(.noteReceived(seq: 5, note: LiveRoomMachineTests.note("a")))
    await Self.wait { log.values == [5] }
    first.incoming.yield(.stroke(seq: 5, stroke: LiveRoomMachineTests.stroke))
    first.incoming.finish()

    var secondSent = second.sent.makeAsyncIterator()
    #expect(await secondSent.next() == .resume(lastSeq: 5))

    // The server replays from the seq asked for; a replay of 5 anyway must not show twice.
    second.incoming.yield(.noteReceived(seq: 5, note: LiveRoomMachineTests.note("a")))
    second.incoming.yield(.noteReceived(seq: 6, note: LiveRoomMachineTests.note("b")))
    await Self.wait { log.values == [5, 6] }
    #expect(log.values == [5, 6])
    #expect(room.state.strokes.isEmpty)
    room.disconnect()
  }

  @Test func theFirstConnectionAsksOnlyForWhatIsNewerThanHistory() async {
    let socket = FakeSocket()
    let room = Self.room(sockets: [socket], lastSeq: 40)
    room.connect()
    var sent = socket.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 40))
    room.send(LiveRoomMachineTests.stroke)
    room.disconnect()
  }
}
