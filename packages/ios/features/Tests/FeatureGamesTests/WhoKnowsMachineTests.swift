import Testing
import Wire

@testable import FeatureGames

@Suite struct WhoKnowsMachineTests {
  typealias M = WhoKnowsMachine

  static let me = UserId("user-me")
  static let partner = UserId("user-partner")
  static let today = GuessRound(
    id: "2026-11-06", subject: partner, questions: [1, 2, 3], closesAt: 0)
  static let score = GuessScore(weekOf: "2026-11-02")

  static func response(
    _ round: GuessRound = today, answers: [GuessAnswer] = [], partnerAnswered: Int = 0,
    reveal: [GuessReveal]? = nil
  ) -> GuessResponse {
    GuessResponse(
      round: round, answers: answers, partnerAnswered: partnerAnswered, reveal: reveal,
      score: score)
  }

  static let playing: M.State = {
    let (state, _) = M.transition(
      .unread(me, .reading(request: 1)), .read(response(), request: 1))
    return state
  }()

  static func round(_ state: M.State) -> M.Round? {
    if case .playing(let round) = state { round } else { nil }
  }

  @Test func theFirstReadOpensTheRoundAndAFailureIsOffline() {
    #expect(M.State.initial(viewer: nil) == .unpaired)
    let (reading, outputs) = M.transition(.initial(viewer: Self.me), .loadAsked)
    #expect(outputs == [.read(request: 1)])
    let (offline, _) = M.transition(reading, .readFailed(request: 1))
    #expect(offline == .unreachable(Self.me, .idle(last: 1)))
    let (again, retry) = M.transition(offline, .loadAsked)
    #expect(retry == [.read(request: 2)])
    let (open, _) = M.transition(again, .read(Self.response(), request: 2))
    #expect(Self.round(open)?.next == 1)
  }

  @Test func anAnswerMovesOnAtOnceAndGoesToTheRoom() {
    let (state, outputs) = M.transition(Self.playing, .answerTapped(question: 1, option: 2))
    #expect(outputs == [.answer(GuessAnswerRequest(round: "2026-11-06", question: 1, option: 2))])
    #expect(Self.round(state)?.next == 2)
    let confirmed = Self.response(answers: [GuessAnswer(question: 1, option: 2)])
    let (done, _) = M.transition(state, .answered(question: 1, confirmed))
    #expect(Self.round(done)?.pending == [])
    #expect(Self.round(done)?.answers == [GuessAnswer(question: 1, option: 2)])
  }

  @Test func anAnswerThatDidNotReachTheRoomOpensItsQuestionAgain() {
    let (sent, _) = M.transition(Self.playing, .answerTapped(question: 1, option: 2))
    let (state, outputs) = M.transition(sent, .answerFailed(question: 1, .unreachable))
    #expect(outputs.isEmpty)
    #expect(Self.round(state)?.unsent == true)
    #expect(Self.round(state)?.next == 1)
    let (again, _) = M.transition(state, .answerTapped(question: 1, option: 2))
    #expect(Self.round(again)?.unsent == false)
  }

  @Test func aRefusedAnswerReadsTheRoomAgain() {
    let (sent, _) = M.transition(Self.playing, .answerTapped(question: 1, option: 2))
    let (state, outputs) = M.transition(sent, .answerFailed(question: 1, .refused))
    #expect(outputs == [.read(request: 2)])
    #expect(Self.round(state)?.unsent == false)
  }

  @Test func theSocketsProgressAndRevealOnlyGrow() {
    let (state, _) = Self.run(
      Self.playing, .progressed(round: "2026-11-06", answered: 2),
      .progressed(round: "2026-11-06", answered: 1), .progressed(round: "2026-11-05", answered: 3))
    #expect(Self.round(state)?.response.partnerAnswered == 2)

    let reveal = [GuessReveal(question: 1, truth: 0, guess: 0, hit: true)]
    let (revealed, _) = M.transition(
      state, .revealed(round: "2026-11-06", reveal: reveal, score: Self.score))
    #expect(Self.round(revealed)?.response.reveal == reveal)
    let (read, _) = Self.run(revealed, .loadAsked, .read(Self.response(), request: 2))
    #expect(Self.round(read)?.response.reveal == reveal, "an older read can't hide the reveal")
  }

  @Test func aLateAnswerAboutAnEarlierDayIsDropped() {
    let yesterday = GuessRound(id: "2026-11-05", subject: Self.me, questions: [1], closesAt: 0)
    let (state, _) = Self.run(Self.playing, .loadAsked, .read(Self.response(yesterday), request: 2))
    #expect(Self.round(state)?.response.round.id == "2026-11-06")
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

  static let revealed: M.State = {
    let reveal = [GuessReveal(question: 1, truth: 0, guess: 0, hit: true)]
    let (state, _) = M.transition(
      playing, .revealed(round: "2026-11-06", reveal: reveal, score: score))
    return state
  }()

  @Test(arguments: [
    (M.State.unpaired, M.Event.loadAsked),
    (.unpaired, .answerTapped(question: 1, option: 0)),
    (.unread(me, .idle(last: 0)), .read(response(), request: 1)),
    (.unread(me, .idle(last: 0)), .progressed(round: "2026-11-06", answered: 1)),
    (.unread(me, .reading(request: 1)), .loadAsked),
    (.unreachable(me, .idle(last: 1)), .answerTapped(question: 1, option: 0)),
    (.unread(me, .reading(request: 2)), .readFailed(request: 1)),
    (playing, .answerTapped(question: 2, option: 0)),
    (playing, .answerFailed(question: 1, .unreachable)),
    (playing, .progressed(round: "2026-11-05", answered: 3)),
    (revealed, .answerTapped(question: 1, option: 0)),
  ])
  func rejected(state: M.State, event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
