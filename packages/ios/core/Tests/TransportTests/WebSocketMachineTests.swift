import Testing
import Wire

@testable import Transport

@Suite struct WebSocketMachineTests {
  typealias Machine = WebSocketMachine
  typealias State = Machine.State

  static let stroke = Stroke(color: "#000", width: 1, points: [Point(x: 0, y: 0)])

  static func state(_ phase: State.Phase, lastSeq: Int? = nil, attempt: Int = 1) -> State {
    State(phase: phase, lastSeq: lastSeq, attempt: attempt)
  }

  @Test func connectStartsAttemptOneWithATimeoutAskingForNotesFromZero() {
    let (state, outputs) = Machine.transition(State.initial, .connectRequested)
    #expect(state == Self.state(.connecting(failures: 0), attempt: 1))
    #expect(outputs == [.open(attempt: 1, resumeFrom: 0), .startConnectTimeout(attempt: 1)])
  }

  @Test func openingStartsTheStabilityTimer() {
    let (state, outputs) = Machine.transition(
      Self.state(.connecting(failures: 0)), .opened(attempt: 1))
    #expect(state == Self.state(.connected(failures: 0)))
    #expect(outputs == [.startStabilityTimer(attempt: 1)])
  }

  static let note = Note.photo(
    id: NoteId("n"), author: UserId("u"), sentAt: 0, image: MediaKey("k"))

  @Test func aLiveStrokeDoesNotAdvanceLastSeq() {
    let message = ServerMessage.stroke(seq: 9, stroke: Self.stroke)
    let (state, outputs) = Machine.transition(
      Self.state(.connected(failures: 0), lastSeq: 3), .received(attempt: 1, message))
    #expect(state.lastSeq == 3)
    #expect(outputs == [.deliver(message)])
  }

  @Test func sequencedMessagesAdvanceLastSeqAndAreDelivered() {
    let message = ServerMessage.noteReceived(seq: 4, note: Self.note)
    let (state, outputs) = Machine.transition(
      Self.state(.connected(failures: 0)), .received(attempt: 1, message))
    #expect(state == Self.state(.connected(failures: 0), lastSeq: 4))
    #expect(outputs == [.deliver(message)])
  }

  @Test func lastSeqNeverMovesBackwards() {
    let message = ServerMessage.noteReceived(seq: 2, note: Self.note)
    let (state, _) = Machine.transition(
      Self.state(.connected(failures: 0), lastSeq: 9), .received(attempt: 1, message))
    #expect(state.lastSeq == 9)
  }

  @Test func presenceDoesNotChangeLastSeq() {
    let (state, outputs) = Machine.transition(
      Self.state(.connected(failures: 0), lastSeq: 3), .received(attempt: 1, .presence(.drawing)))
    #expect(state.lastSeq == 3)
    #expect(outputs == [.deliver(.presence(.drawing))])
  }

  @Test func dropWhileConnectedClosesAndBacksOffKeepingLastSeq() {
    let (state, outputs) = Machine.transition(
      Self.state(.connected(failures: 0), lastSeq: 7), .dropped(attempt: 1))
    #expect(state == Self.state(.backingOff(failures: 1), lastSeq: 7))
    #expect(outputs == [.close(attempt: 1), .scheduleRetry(afterFailures: 1, attempt: 1)])
  }

  @Test func retryStartsTheNextAttempt() {
    let (state, outputs) = Machine.transition(
      Self.state(.backingOff(failures: 1), lastSeq: 7), .retryElapsed(attempt: 1))
    #expect(state == Self.state(.connecting(failures: 1), lastSeq: 7, attempt: 2))
    #expect(outputs == [.open(attempt: 2, resumeFrom: 7), .startConnectTimeout(attempt: 2)])
  }

  @Test func failedAttemptsBackOffLonger() {
    let (state, outputs) = Machine.transition(
      Self.state(.connecting(failures: 1), attempt: 2), .dropped(attempt: 2))
    #expect(state == Self.state(.backingOff(failures: 2), attempt: 2))
    #expect(outputs == [.close(attempt: 2), .scheduleRetry(afterFailures: 2, attempt: 2)])
  }

  @Test func reopeningKeepsLastSeq() {
    let (state, outputs) = Machine.transition(
      Self.state(.connecting(failures: 2), lastSeq: 7, attempt: 3), .opened(attempt: 3))
    #expect(state == Self.state(.connected(failures: 2), lastSeq: 7, attempt: 3))
    #expect(outputs == [.startStabilityTimer(attempt: 3)])
  }

  @Test func aConnectThatNeverAnswersTimesOutAndRetries() {
    var state = State.initial
    var outputs: [Machine.Output] = []
    let events: [Machine.Event] = [
      .connectRequested, .connectTimedOut(attempt: 1), .retryElapsed(attempt: 1),
    ]
    for event in events {
      (state, outputs) = Machine.transition(state, event)
    }
    #expect(state == Self.state(.connecting(failures: 1), attempt: 2))
    #expect(outputs == [.open(attempt: 2, resumeFrom: 0), .startConnectTimeout(attempt: 2)])
  }

  @Test func dropThenResumeEndToEnd() {
    var state = State.initial
    var outputs: [Machine.Output] = []
    let events: [Machine.Event] = [
      .connectRequested, .opened(attempt: 1),
      .received(attempt: 1, .noteReceived(seq: 5, note: Self.note)), .dropped(attempt: 1),
      .retryElapsed(attempt: 1), .dropped(attempt: 2), .retryElapsed(attempt: 2),
    ]
    for event in events {
      (state, outputs) = Machine.transition(state, event)
    }
    #expect(state == Self.state(.connecting(failures: 2), lastSeq: 5, attempt: 3))
    #expect(outputs == [.open(attempt: 3, resumeFrom: 5), .startConnectTimeout(attempt: 3)])
  }

  @Test(
    "Disconnecting from any live phase closes the attempt and keeps lastSeq",
    arguments: [
      State.Phase.connecting(failures: 0), .connected(failures: 0), .backingOff(failures: 2),
    ]
  )
  func disconnect(from phase: State.Phase) {
    let (next, outputs) = Machine.transition(
      Self.state(phase, lastSeq: 3), .disconnectRequested)
    #expect(next == Self.state(.idle, lastSeq: 3))
    #expect(outputs == [.close(attempt: 1)])
  }

  @Test func connectedSendsClientMessages() {
    let (state, outputs) = Machine.transition(
      Self.state(.connected(failures: 0)), .sendRequested(.presence(.drawing)))
    #expect(state == Self.state(.connected(failures: 0)))
    #expect(outputs == [.send(.presence(.drawing), attempt: 1)])
  }

  @Test func reconnectingAfterDisconnectUsesANewAttempt() {
    let (state, outputs) = Machine.transition(
      Self.state(.idle, lastSeq: 3), .connectRequested)
    #expect(state == Self.state(.connecting(failures: 0), lastSeq: 3, attempt: 2))
    #expect(outputs == [.open(attempt: 2, resumeFrom: 3), .startConnectTimeout(attempt: 2)])
  }

  @Test(
    "A socket that opens when nobody waits for it is closed",
    arguments: [State.Phase.idle, .backingOff(failures: 1)]
  )
  func lateOpenIsClosed(phase: State.Phase) {
    let state = Self.state(phase)
    let (next, outputs) = Machine.transition(state, .opened(attempt: 1))
    #expect(next == state)
    #expect(outputs == [.close(attempt: 1)])
  }

  @Test(
    "Results from an old attempt change nothing",
    arguments: [
      Machine.Event.dropped(attempt: 1),
      .received(attempt: 1, .presence(.drawing)),
      .connectTimedOut(attempt: 1),
      .retryElapsed(attempt: 1),
    ]
  )
  func staleEventsAreIgnored(event: Machine.Event) {
    for phase in [
      State.Phase.connecting(failures: 0), .connected(failures: 0), .backingOff(failures: 1),
    ] {
      let state = Self.state(phase, attempt: 2)
      let (next, outputs) = Machine.transition(state, event)
      #expect(next == state)
      #expect(outputs.isEmpty)
    }
  }

  @Test func staleOpenedClosesItsOwnSocketOnly() {
    let state = Self.state(.connecting(failures: 1), attempt: 2)
    let (next, outputs) = Machine.transition(state, .opened(attempt: 1))
    #expect(next == state)
    #expect(outputs == [.close(attempt: 1)])
  }

  @Test(
    "Events that do not apply leave the state alone and do no work",
    arguments: [
      (State.Phase.idle, Machine.Event.disconnectRequested),
      (.idle, .dropped(attempt: 1)),
      (.idle, .received(attempt: 1, .presence(.idle))),
      (.idle, .retryElapsed(attempt: 1)),
      (.idle, .connectTimedOut(attempt: 1)),
      (.idle, .sendRequested(.presence(.idle))),
      (.connecting(failures: 0), .connectRequested),
      (.connecting(failures: 0), .received(attempt: 1, .presence(.idle))),
      (.connecting(failures: 0), .retryElapsed(attempt: 1)),
      (.connecting(failures: 0), .sendRequested(.presence(.idle))),
      (.connected(failures: 0), .connectRequested),
      (.connected(failures: 0), .opened(attempt: 1)),
      (.connected(failures: 0), .retryElapsed(attempt: 1)),
      (.connected(failures: 0), .connectTimedOut(attempt: 1)),
      (.backingOff(failures: 1), .connectRequested),
      (.backingOff(failures: 1), .dropped(attempt: 1)),
      (.backingOff(failures: 1), .received(attempt: 1, .presence(.idle))),
      (.backingOff(failures: 1), .connectTimedOut(attempt: 1)),
      (.backingOff(failures: 1), .sendRequested(.presence(.idle))),
    ]
  )
  func ignoredEvents(phase: State.Phase, event: Machine.Event) {
    let state = Self.state(phase, lastSeq: 1)
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test func retryDelayDoublesThenCaps() {
    #expect(Machine.retryDelay(afterFailures: 1) == .seconds(1))
    #expect(Machine.retryDelay(afterFailures: 2) == .seconds(2))
    #expect(Machine.retryDelay(afterFailures: 4) == .seconds(8))
    #expect(Machine.retryDelay(afterFailures: 6) == .seconds(32))
    #expect(Machine.retryDelay(afterFailures: 60) == .seconds(32))
  }

  @Test func aConnectionThatDropsAtOnceBacksOffLongerEachTime() {
    var state = State.initial
    var delays: [Int] = []
    var events: [Machine.Event] = [.connectRequested]
    var attempt = 1
    for _ in 0..<4 {
      events += [
        .opened(attempt: attempt), .dropped(attempt: attempt), .retryElapsed(attempt: attempt),
      ]
      attempt += 1
    }
    for event in events {
      let (next, outputs) = Machine.transition(state, event)
      state = next
      for case .scheduleRetry(let failures, _) in outputs { delays.append(failures) }
    }
    #expect(delays == [1, 2, 3, 4])
  }

  @Test func aConnectionThatStaysUpStartsOverFromOneSecond() {
    var state = State.initial
    let events: [Machine.Event] = [
      .connectRequested, .opened(attempt: 1), .dropped(attempt: 1), .retryElapsed(attempt: 1),
      .opened(attempt: 2), .stable(attempt: 2),
    ]
    for event in events { (state, _) = Machine.transition(state, event) }
    #expect(state == Self.state(.connected(failures: 0), attempt: 2))
    let (next, outputs) = Machine.transition(state, .dropped(attempt: 2))
    #expect(next == Self.state(.backingOff(failures: 1), attempt: 2))
    #expect(outputs == [.close(attempt: 2), .scheduleRetry(afterFailures: 1, attempt: 2)])
  }

  @Test func aStaleStabilityReportChangesNothing() {
    let state = Self.state(.connected(failures: 3), attempt: 4)
    let (next, outputs) = Machine.transition(state, .stable(attempt: 3))
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test(arguments: [State.Phase.idle, .connecting(failures: 1), .backingOff(failures: 1)])
  func stabilityOutsideAConnectionChangesNothing(_ phase: State.Phase) {
    let state = Self.state(phase)
    let (next, outputs) = Machine.transition(state, .stable(attempt: 1))
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
