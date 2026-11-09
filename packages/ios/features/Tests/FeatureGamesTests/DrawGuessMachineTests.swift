import Foundation
import Testing
import Wire

@testable import FeatureGames

@Suite struct DrawGuessMachineTests {
  typealias M = DrawGuessMachine

  static let me = UserId("user-me")
  static let partner = UserId("user-partner")
  /// "cat" among nine decoys: c is tile 1, a tile 3, t tile 6.
  static let catTiles = ["x", "c", "q", "a", "z", "m", "t", "p", "r", "o", "b", "k"]
  static let key = IdempotencyKey("key-1")
  static let png = Data([1])
  static let strokes = CompactStrokes(strokes: [])

  static func riddle(
    _ id: String = "riddle-1", by drawer: UserId = partner, word: String = "cat", at: Int = 1,
    tries: Int = 0, hints: Int = 0, revealed: [RevealedLetter] = [], state: RiddleState = .open
  ) -> Riddle {
    Riddle(
      id: RiddleId(id), drawer: drawer, shape: word.split(separator: " ").map(\.count),
      tiles: catTiles, revealed: revealed, hints: hints, tries: tries, state: state,
      word: drawer == me || state != .open ? word : nil, compact: strokes,
      image: MediaKey("media-1"), at: at)
  }

  static func playing(_ open: [Riddle] = [], series: Int = 0) -> M.State {
    let (state, _) = M.transition(
      .unread(me, .reading(request: 1)),
      .read(RiddlesResponse(open: open, series: series), request: 1))
    return state
  }

  static func game(_ state: M.State) -> M.Game {
    guard case .playing(let game) = state else {
      Issue.record("not playing: \(state)")
      return M.Game(viewer: me, board: RiddlesResponse(), turn: .waiting, read: .idle(last: 0))
    }
    return game
  }

  static func guess(_ state: M.State) -> M.Guess? {
    if case .guessing(let guess) = game(state).turn { guess } else { nil }
  }

  static func run(_ state: M.State, _ events: M.Event...) -> (M.State, [M.Output]) {
    var state = state
    var outputs: [M.Output] = []
    for event in events {
      let (next, out) = M.transition(state, event)
      state = next
      outputs += out
    }
    return (state, outputs)
  }

  // MARK: Reading

  @Test func noViewerIsUnpaired() {
    #expect(M.State.initial(viewer: nil) == .unpaired)
    #expect(M.State.initial(viewer: Self.me) == .unread(Self.me, .idle(last: 0)))
  }

  @Test func theFirstReadOpensTheGameAndAFailureIsOffline() {
    let (reading, outputs) = M.transition(.initial(viewer: Self.me), .loadAsked)
    #expect(reading == .unread(Self.me, .reading(request: 1)))
    #expect(outputs == [.read(request: 1)])

    let (offline, _) = M.transition(reading, .readFailed(request: 1))
    #expect(offline == .unreachable(Self.me, .idle(last: 1)))
    let (again, retry) = M.transition(offline, .loadAsked)
    #expect(again == .unreachable(Self.me, .reading(request: 2)), "offline while it tries again")
    #expect(retry == [.read(request: 2)])

    let (open, _) = M.transition(again, .read(RiddlesResponse(), request: 2))
    #expect(Self.game(open).turn == .drawing(.idle))
    #expect(Self.game(open).read == .idle(last: 2))
  }

  @Test func theTurnFollowsTheBoard() {
    #expect(Self.game(Self.playing()).turn == .drawing(.idle))
    #expect(Self.game(Self.playing([Self.riddle(by: Self.me)])).turn == .waiting)
    // Guessing comes before waiting on one's own riddle.
    let both = Self.playing([Self.riddle(by: Self.me, at: 1), Self.riddle("riddle-2", at: 2)])
    #expect(Self.guess(both)?.riddle == RiddleId("riddle-2"))
  }

  @Test func aSecondLoadWhileOneIsOutSendsNothing() {
    let (state, outputs) = Self.run(Self.playing(), .loadAsked, .loadAsked)
    #expect(outputs == [.read(request: 2)])
    let (late, _) = M.transition(state, .read(RiddlesResponse(), request: 1))
    #expect(Self.game(late).read == .reading(request: 2), "an earlier answer leaves the read out")
  }

  // MARK: Guessing

  @Test func theLastTileSendsTheWordAsATry() {
    let start = Self.playing([Self.riddle()])
    let (placing, none) = Self.run(
      start, .tilePlaced(1, key: Self.key), .tilePlaced(3, key: Self.key))
    #expect(none.isEmpty)
    #expect(Self.guess(placing)?.placed == [0: 1, 1: 3])
    let (trying, outputs) = M.transition(placing, .tilePlaced(6, key: Self.key))
    #expect(outputs == [.guess(RiddleId("riddle-1"), key: Self.key, guess: "cat")])
    #expect(Self.guess(trying)?.isBusy == true)
  }

  @Test func aWrongTryClearsTheTilesAndCountsAMiss() {
    let (trying, _) = Self.run(
      Self.playing([Self.riddle()]), .tilePlaced(0, key: Self.key), .tilePlaced(2, key: Self.key),
      .tilePlaced(4, key: Self.key))
    let answer = GuessRiddleResponse(riddle: Self.riddle(tries: 1), right: false)
    let (state, _) = M.transition(trying, .guessed(RiddleId("riddle-1"), answer))
    #expect(Self.guess(state)?.placed == [:])
    #expect(Self.guess(state)?.step == .picking)
    #expect(Self.game(state).misses == 1)
  }

  @Test func aRightTryEndsTheRoundAndCountsTheSeries() {
    let (trying, _) = Self.run(
      Self.playing([Self.riddle()], series: 2), .tilePlaced(1, key: Self.key),
      .tilePlaced(3, key: Self.key), .tilePlaced(6, key: Self.key))
    let solved = Self.riddle(tries: 1, state: .solved(at: 5))
    let (ended, _) = M.transition(
      trying, .guessed(RiddleId("riddle-1"), GuessRiddleResponse(riddle: solved, right: true)))
    #expect(Self.game(ended).turn == .ended(solved))
    #expect(Self.game(ended).board.series == 3)
    let (drawing, _) = M.transition(ended, .drawNextTapped)
    #expect(Self.game(drawing).turn == .drawing(.idle))
  }

  /// A solved or given-up round left its tiles placed, and the partner's next riddle started with
  /// them: a wrong try sent on the first tap.
  @Test func theNextRiddleStartsWithNoTilesPlaced() {
    let (placed, _) = Self.run(
      Self.playing([Self.riddle()]), .tilePlaced(1, key: Self.key), .tilePlaced(3, key: Self.key),
      .giveUpTapped)
    let givenUp = Self.riddle(state: .givenUp(at: 5))
    let (ended, _) = Self.run(placed, .gaveUp(givenUp), .drawNextTapped)
    let next = Self.riddle("riddle-2", word: "cats", at: 9)
    let (guessing, outputs) = Self.run(ended, .changed(next), .tilePlaced(1, key: Self.key))
    #expect(Self.guess(guessing)?.riddle == RiddleId("riddle-2"))
    #expect(Self.guess(guessing)?.placed == [0: 1])
    #expect(outputs.isEmpty)
  }

  @Test func aTryThatDidNotReachTheRoomGoesAgainWithItsKey() {
    let (trying, _) = Self.run(
      Self.playing([Self.riddle()]), .tilePlaced(1, key: Self.key), .tilePlaced(3, key: Self.key),
      .tilePlaced(6, key: Self.key))
    let (unsent, none) = M.transition(trying, .guessFailed(RiddleId("riddle-1"), .unreachable))
    #expect(none.isEmpty)
    #expect(Self.guess(unsent)?.step == .notSent)
    #expect(Self.guess(unsent)?.placed == [0: 1, 1: 3, 2: 6])

    let (again, outputs) = Self.run(
      unsent, .tileTakenBack(slot: 2), .tilePlaced(6, key: IdempotencyKey("key-2")))
    #expect(outputs == [.guess(RiddleId("riddle-1"), key: Self.key, guess: "cat")])
    #expect(Self.guess(again)?.isBusy == true)
  }

  @Test func aRefusedTryReadsTheRoomAgain() {
    let (trying, _) = Self.run(
      Self.playing([Self.riddle()]), .tilePlaced(1, key: Self.key), .tilePlaced(3, key: Self.key),
      .tilePlaced(6, key: Self.key))
    let (state, outputs) = M.transition(trying, .guessFailed(RiddleId("riddle-1"), .refused))
    #expect(outputs == [.read(request: 2)])
    #expect(Self.guess(state)?.placed == [:])
    #expect(Self.guess(state)?.retry == nil)
  }

  @Test func aHintClearsThePlacedTiles() {
    let (hinting, outputs) = Self.run(
      Self.playing([Self.riddle()]), .tilePlaced(1, key: Self.key), .hintTapped)
    #expect(outputs == [.hint(RiddleId("riddle-1"))])
    let (state, _) = M.transition(hinting, .hinted(Self.riddle(hints: 1)))
    #expect(Self.guess(state)?.placed == [:])
    #expect(Self.guess(state)?.step == .picking)
    #expect(Self.game(state).theirs?.hints == 1)
  }

  @Test func theSocketEndingTheRoundMidTryLeavesTheAnswerNothingToDo() {
    let (trying, _) = Self.run(
      Self.playing([Self.riddle()]), .tilePlaced(1, key: Self.key), .tilePlaced(3, key: Self.key),
      .tilePlaced(6, key: Self.key))
    let solved = Self.riddle(tries: 3, state: .solved(at: 9))
    let (ended, _) = M.transition(trying, .changed(solved))
    #expect(Self.game(ended).turn == .ended(solved))
    let late = GuessRiddleResponse(riddle: Self.riddle(tries: 1), right: false)
    let (after, outputs) = M.transition(ended, .guessed(RiddleId("riddle-1"), late))
    #expect(Self.game(after).turn == .ended(solved))
    #expect(Self.game(after).misses == 0)
    #expect(outputs.isEmpty)
  }

  @Test func staleFramesDoNotGoBack() {
    let (state, _) = Self.run(
      Self.playing([Self.riddle(tries: 2)]), .changed(Self.riddle(tries: 1)))
    #expect(Self.game(state).theirs?.tries == 2)
    let (read, _) = Self.run(
      state, .loadAsked, .read(RiddlesResponse(open: [Self.riddle(tries: 0)]), request: 2))
    #expect(Self.game(read).theirs?.tries == 2)
  }

  // MARK: Drawing

  @Test func aSendThatDidNotReachTheRoomKeepsItsIDForTheSameWord() {
    let id1 = RiddleId("riddle-a")
    let id2 = RiddleId("riddle-b")
    let (sending, outputs) = M.transition(
      Self.playing(), .sendTapped(word: "cat", png: Self.png, compact: Self.strokes, id: id1))
    #expect(
      outputs == [.send(M.Upload(id: id1, word: "cat", png: Self.png, compact: Self.strokes))])
    let (unsent, _) = M.transition(sending, .sendFailed(id1, .unreachable))
    #expect(Self.game(unsent).turn == .drawing(.notSent(M.Draft(id: id1, word: "cat"))))
    let (again, retry) = M.transition(
      unsent, .sendTapped(word: "cat", png: Self.png, compact: Self.strokes, id: id2))
    #expect(retry == [.send(M.Upload(id: id1, word: "cat", png: Self.png, compact: Self.strokes))])
    let (waiting, _) = M.transition(again, .sent(Self.riddle("riddle-a", by: Self.me)))
    #expect(Self.game(waiting).turn == .waiting)
  }

  /// "Didn't reach" from a failed send showed on the guess screen once the partner's riddle came.
  @Test func aFailedSendDoesNotFollowToTheGuessScreen() {
    let (unsent, _) = Self.run(
      Self.playing(),
      .sendTapped(word: "cat", png: Self.png, compact: Self.strokes, id: RiddleId("riddle-a")),
      .sendFailed(RiddleId("riddle-a"), .unreachable))
    let (guessing, _) = M.transition(unsent, .changed(Self.riddle()))
    #expect(Self.guess(guessing)?.step == .picking)
  }

  // MARK: Rejected

  static let trying: M.State = {
    let (state, _) = run(
      playing([riddle()]), .tilePlaced(1, key: key), .tilePlaced(3, key: key),
      .tilePlaced(6, key: key))
    return state
  }()

  @Test(arguments: [
    (M.State.unpaired, M.Event.loadAsked),
    (.unpaired, .changed(riddle())),
    (.unpaired, .read(RiddlesResponse(), request: 1)),
    (.unread(me, .idle(last: 0)), .read(RiddlesResponse(), request: 1)),
    (.unread(me, .idle(last: 0)), .readFailed(request: 1)),
    (.unread(me, .reading(request: 2)), .readFailed(request: 1)),
    (.unread(me, .reading(request: 1)), .loadAsked),
    (.unread(me, .idle(last: 0)), .tilePlaced(1, key: key)),
    (.unreachable(me, .idle(last: 1)), .hintTapped),
    (playing(), .tilePlaced(1, key: key)),
    (playing(), .hintTapped),
    (playing(), .giveUpTapped),
    (playing(), .drawNextTapped),
    (playing([riddle()]), .tileTakenBack(slot: 0)),
    (playing([riddle()]), .tilePlaced(99, key: key)),
    (playing([riddle()]), .sendTapped(word: "cat", png: png, compact: strokes, id: key)),
    (playing([riddle(by: me)]), .sendTapped(word: "cat", png: png, compact: strokes, id: key)),
    // Hints show all letters but one at most.
    (
      playing([
        riddle(
          hints: 3,
          revealed: [RevealedLetter(index: 0, letter: "c"), RevealedLetter(index: 2, letter: "t")])
      ]), .hintTapped
    ),
    (trying, .tilePlaced(0, key: key)),
    (trying, .tileTakenBack(slot: 0)),
    (trying, .hintTapped),
    (trying, .giveUpTapped),
    (playing(), .sendFailed(RiddleId("riddle-x"), .unreachable)),
    (playing([riddle()]), .guessFailed(RiddleId("riddle-1"), .unreachable)),
  ])
  func rejected(state: M.State, event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
