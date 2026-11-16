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

  @Test func presenceAwayDropsTheDrawingAndSaysNothing() {
    var (state, _) = M.transition(Self.online, .received(.stroke(seq: 1, stroke: Self.stroke)))
    (state, _) = M.transition(state, .received(.presence(.away)))
    #expect(state.strokes.isEmpty)
    #expect(state.partner == .away)
    #expect(state.presenceText == nil)
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

  static let begin = LiveStrokeStart(id: 7, color: "#7B4FE0", width: 14)

  @Test func aStreamedStrokeGrowsWhileOpenAndLandsWhenItEnds() {
    var (state, _) = M.transition(Self.online, .received(.strokeBegin(Self.begin)))
    #expect(state.partner == .drawing)
    (state, _) = M.transition(
      state, .received(.strokePoints(id: 7, points: [Point(x: 1, y: 2), Point(x: 3, y: 4)])))
    (state, _) = M.transition(state, .received(.strokePoints(id: 7, points: [Point(x: 5, y: 6)])))
    #expect(state.openStrokes[7]?.points.count == 3)
    #expect(state.strokes.isEmpty)

    (state, _) = M.transition(state, .received(.strokeEnd(id: 7)))
    #expect(state.openStrokes.isEmpty)
    #expect(state.strokes.map(\.color) == ["#7B4FE0"])
    #expect(state.strokes.first?.points.count == 3)
  }

  @Test func pointsForAStrokeNeverBegunAreIgnored() {
    let (state, _) = M.transition(
      Self.online, .received(.strokePoints(id: 1, points: [Point(x: 1, y: 2)])))
    #expect(state.openStrokes.isEmpty)
  }

  @Test func aDroppedStrokeIsDiscarded() {
    var (state, _) = M.transition(Self.online, .received(.strokeBegin(Self.begin)))
    (state, _) = M.transition(state, .received(.strokePoints(id: 7, points: [Point(x: 1, y: 2)])))
    (state, _) = M.transition(state, .received(.strokeDropped(id: 7)))
    #expect(state.openStrokes.isEmpty)
    #expect(state.strokes.isEmpty)
  }

  @Test func clearWipesFinishedAndOpenStrokes() {
    var (state, _) = M.transition(Self.online, .received(.stroke(seq: 1, stroke: Self.stroke)))
    (state, _) = M.transition(state, .received(.strokeBegin(Self.begin)))
    (state, _) = M.transition(state, .received(.clear))
    #expect(state.strokes.isEmpty)
    #expect(state.openStrokes.isEmpty)
  }

  @Test func anOpenStrokeIsBounded() {
    var (state, _) = M.transition(Self.online, .received(.strokeBegin(Self.begin)))
    let batch = Array(repeating: Point(x: 1, y: 1), count: LiveStrokeStart.maxPoints)
    for _ in 0...(M.openPointLimit / batch.count) {
      (state, _) = M.transition(state, .received(.strokePoints(id: 7, points: batch)))
    }
    #expect(state.openStrokes[7]?.points.count == M.openPointLimit)
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
    sockets: [FakeSocket], lastSeq: Int? = nil, log: NoteLog = NoteLog(),
    clock: TestClock = TestClock()
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
      lastSeq: lastSeq, onNote: { seq, _ in log.add(seq) },
      now: { clock.now }, wait: { clock.advance($0) })
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

  @Test func aClumpOfPointsIsDrawnInOrderAtTheRelayPace() async {
    let socket = FakeSocket()
    let clock = TestClock()
    let room = Self.room(sockets: [socket], clock: clock)
    room.connect()
    var sent = socket.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 0))
    await Self.wait { room.isOnline }

    socket.incoming.yield(.strokeBegin(LiveStrokeStart(id: 2, color: "#7B4FE0", width: 0.03)))
    // Five frames relayed 40 ms apart reach this phone at the same moment; the end follows.
    let frames = (0..<5).map { [Point(x: Double($0), y: 0)] }
    for (index, points) in frames.enumerated() {
      socket.incoming.yield(.strokePoints(id: 2, points: points, relayedAt: 1_000 + index * 40))
    }
    socket.incoming.yield(.strokeEnd(id: 2))

    await Self.wait { room.state.strokes.count == 1 }
    #expect(room.state.strokes.first?.points == frames.flatMap { $0 })
    // Some were held, never longer than the four early frames' 4 × 40 ms replayed faster than
    // real time. Frames delivered after the clock moved on wait less, so this is a bound.
    #expect(clock.waited > 0)
    #expect(clock.waited <= 0.16 / LivePacer.catchUp + 1e-6)
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

@Suite struct LiveFrameSendingTests {
  @Test func liveFramesGoOutOnlyWhileOnline() {
    let frame = ClientMessage.strokeEnd(id: 1)
    #expect(LiveRoomMachine.transition(LiveRoomMachine.State(), .liveFrame(frame)).1.isEmpty)
    #expect(
      LiveRoomMachine.transition(LiveRoomMachine.State(isOnline: true), .liveFrame(frame)).1
        == [.send(frame)])
  }
}

/// A clock that moves only when the pacer waits on it.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var time = 10.0
  private var total = 0.0

  var now: Double { lock.withLock { time } }
  /// Everything the pacer has waited, in seconds.
  var waited: Double { lock.withLock { total } }

  func advance(_ seconds: Double) {
    lock.withLock {
      time += seconds
      total += seconds
    }
  }
}

@Suite struct LiveCanvasEditTests {
  typealias M = LiveRoomMachine

  static func live(_ id: Int, points: Int = 1) -> LiveStroke {
    LiveStroke(
      id: id,
      stroke: Stroke(
        color: "#A5442B", width: 0.03,
        points: (0..<points).map { Point(x: Double($0) / 10_000, y: 0.5) }))
  }

  static let online = M.State(isOnline: true, partner: .drawing)

  /// The partner drew strokes 1 and 2, live.
  static var partnerDrewTwo: M.State {
    var state = online
    for id in [1, 2] {
      (state, _) = M.transition(
        state, .received(.strokeBegin(LiveStrokeStart(id: id, color: "#A5442B", width: 0.03))))
      (state, _) = M.transition(
        state, .received(.strokePoints(id: id, points: [Point(x: 0.1, y: 0.1)])))
      (state, _) = M.transition(state, .received(.strokeEnd(id: id)))
    }
    return state
  }

  @Test func anUndoOnTheirPhoneTakesTheStrokeOffThisOne() {
    let (state, outputs) = M.transition(Self.partnerDrewTwo, .received(.strokesKept(ids: [1])))
    #expect(state.partnerStrokes.map(\.id) == [1])
    #expect(outputs.isEmpty)
  }

  @Test func anUndoHereSendsWhichStrokesAreLeft() {
    var state = Self.online
    var outputs: [M.Output]
    for id in [1, 2] {
      (state, _) = M.transition(state, .liveFrame(.strokeEnd(id: id)))
      (state, outputs) = M.transition(
        state, .canvasChanged((1...id).map { Self.live($0) }))
      // A stroke that just ended live is not sent again.
      #expect(outputs.isEmpty)
    }
    (state, outputs) = M.transition(state, .canvasChanged([Self.live(1)]))
    #expect(outputs == [.send(.strokesKept(ids: [1]))])

    // Undoing what is already undone changes nothing, here or on the partner's phone.
    (state, outputs) = M.transition(state, .canvasChanged([Self.live(1)]))
    #expect(outputs.isEmpty)
    let partner = M.transition(Self.partnerDrewTwo, .received(.strokesKept(ids: [1]))).0
    #expect(M.transition(partner, .received(.strokesKept(ids: [1]))).0 == partner)
  }

  @Test func anUndoThatBringsAStrokeBackSendsItWhole() {
    var state = Self.online
    (state, _) = M.transition(state, .liveFrame(.strokeEnd(id: 1)))
    (state, _) = M.transition(state, .canvasChanged([Self.live(1)]))
    (state, _) = M.transition(state, .canvasChanged([]))  // erased
    let (_, outputs) = M.transition(state, .canvasChanged([Self.live(1)]))  // undo
    #expect(outputs == [.send(.strokesShown([Self.live(1)]))])
  }

  @Test func aStrokeSentAgainReplacesItselfInPlace() {
    let again = Stroke(color: "#000000", width: 0.05, points: [Point(x: 0.9, y: 0.9)])
    let (state, _) = M.transition(
      Self.partnerDrewTwo, .received(.strokesShown([LiveStroke(id: 1, stroke: again)])))
    #expect(state.partnerStrokes.map(\.id) == [1, 2])
    #expect(state.partnerStrokes.first?.stroke == again)
  }

  @Test func aReconnectSendsTheWholeCanvasAgainAndConverges() {
    var sender = Self.online
    (sender, _) = M.transition(sender, .liveFrame(.strokeEnd(id: 1)))
    (sender, _) = M.transition(sender, .canvasChanged([Self.live(1)]))
    (sender, _) = M.transition(sender, .linkChanged(online: false))
    // Drawn and undone while the link was down: nothing goes out.
    let (offline, nothing) = M.transition(sender, .canvasChanged([Self.live(1), Self.live(2)]))
    #expect(nothing.isEmpty)
    (sender, _) = M.transition(offline, .canvasChanged([Self.live(2)]))
    let (back, outputs) = M.transition(sender, .linkChanged(online: true))
    #expect(
      outputs == [.send(.strokesShown([Self.live(2)])), .send(.strokesKept(ids: [2]))])
    #expect(back.shown == [2])

    // The partner, who still held stroke 1 from before the drop, ends up with stroke 2 alone.
    var partner = M.State(isOnline: true, partner: .drawing)
    (partner, _) = M.transition(partner, .received(.strokesShown([Self.live(1)])))
    for output in outputs {
      guard case .send(.strokesShown(let strokes)) = output else {
        if case .send(.strokesKept(let ids)) = output {
          (partner, _) = M.transition(partner, .received(.strokesKept(ids: ids)))
        }
        continue
      }
      (partner, _) = M.transition(partner, .received(.strokesShown(strokes)))
    }
    #expect(partner.partnerStrokes.map(\.id) == [2])
  }

  @Test func aPartnerWhoStartsDrawingLateIsSentTheCanvas() {
    var state = M.State(isOnline: true, partner: .idle)
    (state, _) = M.transition(state, .liveFrame(.strokeEnd(id: 4)))
    (state, _) = M.transition(state, .canvasChanged([Self.live(4)]))
    let (drawing, outputs) = M.transition(state, .received(.presence(.drawing)))
    #expect(outputs == [.send(.strokesShown([Self.live(4)])), .send(.strokesKept(ids: [4]))])
    // Presence repeated while they draw sends nothing more.
    #expect(M.transition(drawing, .received(.presence(.drawing))).1.isEmpty)
  }

  @Test func aSentNoteIsNotTouchedByEdits() {
    let note = Note.photo(id: NoteId("n"), author: UserId("them"), sentAt: 1, image: MediaKey("k"))
    var (state, outputs) = M.transition(
      Self.partnerDrewTwo, .received(.noteReceived(seq: 5, note: note)))
    #expect(outputs == [.noteArrived(seq: 5, note)])
    (state, outputs) = M.transition(state, .received(.strokesKept(ids: [])))
    #expect(outputs.isEmpty)
    #expect(state.lastNoteSeq == 5)
    (state, outputs) = M.transition(state, .canvasChanged([]))
    #expect(outputs.isEmpty)
  }

  @Test func aWholeStrokeFrameWithoutAnIdIsNeverDropped() {
    var (state, _) = M.transition(
      Self.online, .received(.stroke(seq: 1, stroke: Self.live(9).stroke)))
    (state, _) = M.transition(state, .received(.strokesKept(ids: [])))
    #expect(state.partnerStrokes.map(\.id) == [nil])
  }

  @Test func longStrokesAreThinnedAndPackedUnderTheFrameBudget() {
    var state = Self.online
    (state, _) = M.transition(state, .canvasChanged([]))
    let strokes = [
      Self.live(1, points: 2_000), Self.live(2, points: 500), Self.live(3, points: 200),
    ]
    let (_, outputs) = M.transition(state, .canvasChanged(strokes))
    let frames = outputs.compactMap { output -> [LiveStroke]? in
      if case .send(.strokesShown(let strokes)) = output { return strokes }
      return nil
    }
    #expect(frames.map { $0.map(\.id) } == [[1], [2, 3]])
    #expect(frames[0][0].stroke.points.count == LiveStroke.maxPoints)
    #expect(frames[0][0].stroke.points.last == strokes[0].stroke.points.last)
  }

  static let rejectedOffline: [M.Event] = [
    .received(.strokesShown([live(1)])),
    .received(.strokesKept(ids: [])),
  ]

  @Test(arguments: rejectedOffline)
  func offlineTheCanvasFramesChangeNothing(_ event: M.Event) {
    let offline = M.State(isOnline: false)
    #expect(M.transition(offline, event) == (offline, []))
  }

  @Test func offlineAnEditIsKeptButNotSent() {
    let (state, outputs) = M.transition(M.State(), .canvasChanged([Self.live(1)]))
    #expect(outputs.isEmpty)
    #expect(state.mine == [Self.live(1)])
    #expect(state.shown.isEmpty)
  }

  @Test func stoppingDrawingForgetsWhatWasShown() {
    var state = Self.online
    (state, _) = M.transition(state, .liveFrame(.strokeEnd(id: 1)))
    (state, _) = M.transition(state, .canvasChanged([Self.live(1)]))
    (state, _) = M.transition(state, .presenceChanged(.idle))
    #expect(state.mine.isEmpty)
    #expect(state.shown.isEmpty)
  }
}
