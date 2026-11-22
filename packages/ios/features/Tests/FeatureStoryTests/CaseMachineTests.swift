import Foundation
import Testing

@testable import FeatureStory
@testable import StoryInterface

@Suite struct CaseMachineTests {
  typealias M = CaseMachine
  let episode = try! EpisodeCatalog.load("fish-plush")
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  func book(_ mine: [CaseMark] = [], _ partner: [CaseMark] = [], days: Int = 0) -> M.Book {
    M.Book(
      episode: episode, side: .first, mine: mine, partner: partner,
      now: now.addingTimeInterval(Double(days) * 86_400), calendar: calendar)
  }

  func found(_ beat: Int, day: Int = 0) -> CaseMark {
    CaseMark(
      episode: episode.id, kind: .found, ref: episode.beats[beat].id,
      at: now.addingTimeInterval(Double(day) * 86_400))
  }

  func named(_ ref: String) -> CaseMark {
    CaseMark(episode: episode.id, kind: .named, ref: ref, at: now)
  }

  /// Every beat compared by both, on its own day.
  var allClues: [CaseMark] { (0..<5).map { found($0, day: $0) } }

  @Test func enablingReadsTheRoomAndTheCaseOpensClosed() {
    let (loading, outputs) = M.transition(.unavailable, .enabled(episode, .first))
    #expect(loading == .loading(episode, .first))
    #expect(outputs == [.fetch])
    let (closed, _) = M.transition(loading, .fetched(.init(mine: [], partner: []), at: now))
    #expect(closed.book?.mine == [])
    #expect(!closed.isOpen)
  }

  @Test func lookingAtTheFirstClueMarksItAndTheRoomsAnswerSettlesIt() {
    let state = M.State.closed(book())
    let (file, _) = M.transition(state, .opened)
    let (clue, _) = M.transition(file, .lookCloser(beat: 0))
    #expect(clue == .clue(book(), beat: 0, .idle))
    let (sending, outputs) = M.transition(clue, .found)
    #expect(sending == .clue(book(), beat: 0, .sending))
    #expect(outputs == [.mark(episode: "fish-plush", kind: .found, ref: "empty-basket")])
    let marks = M.Marks(mine: [found(0)], partner: [])
    let (done, _) = M.transition(sending, .marked(marks, at: now))
    #expect(done == .clue(book([found(0)]), beat: 0, .idle))
  }

  @Test func aFailedWriteCanBeSentAgain() {
    let (failed, _) = M.transition(.clue(book(), beat: 0, .sending), .markFailed)
    #expect(failed == .clue(book(), beat: 0, .failed))
    let (again, outputs) = M.transition(failed, .found)
    #expect(again == .clue(book(), beat: 0, .sending))
    #expect(outputs.count == 1)
  }

  @Test func aBeatThatIsNotOpenCannotBeLookedAt() {
    let file = M.State.file(book())
    #expect(M.transition(file, .lookCloser(beat: 1)).0 == file)
    #expect(M.transition(file, .lookCloser(beat: 9)).0 == file)
    #expect(M.transition(file, .lookCloser(beat: -1)).0 == file)
  }

  @Test func aBeatThatIsOpenTheNextDayCanBeLookedAt() {
    let file = M.State.file(book([found(0)], [found(0)], days: 1))
    #expect(
      M.transition(file, .lookCloser(beat: 1)).0
        == .clue(book([found(0)], [found(0)], days: 1), beat: 1, .idle))
  }

  @Test func aClueAlreadyLookedAtIsNotSentTwice() {
    let state = M.State.clue(book([found(0)]), beat: 0, .idle)
    let (next, outputs) = M.transition(state, .found)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test func namingNeedsEveryBeatAndAChoice() {
    let early = M.State.file(book())
    #expect(M.transition(early, .nameSuspect).0 == early)

    let ready = book(allClues, allClues, days: 9)
    let (naming, _) = M.transition(.file(ready), .nameSuspect)
    #expect(naming == .naming(ready, choice: nil, .idle))
    #expect(M.transition(naming, .confirmName) == (naming, []))
    #expect(M.transition(naming, .choose("nobody")).0 == naming)

    let (chosen, _) = M.transition(naming, .choose("crow"))
    let (sending, outputs) = M.transition(chosen, .confirmName)
    #expect(sending == .naming(ready, choice: "crow", .sending))
    #expect(outputs == [.mark(episode: "fish-plush", kind: .named, ref: "crow")])
    #expect(M.transition(sending, .choose("draft")).0 == sending)
    #expect(M.transition(sending, .confirmName) == (sending, []))

    let answered = book(allClues + [named("crow")], allClues, days: 9)
    let (file, _) = M.transition(
      sending, .marked(.init(mine: answered.mine, partner: answered.partner), at: answered.now))
    #expect(file == .file(answered))
  }

  @Test func theEndingWaitsForBothNamesAndIsMarkedOnce() {
    let waiting = M.State.file(book(allClues + [named("crow")], allClues, days: 9))
    #expect(M.transition(waiting, .watchEnding) == (waiting, []))

    let ready = book(allClues + [named("crow")], allClues + [named("draft")], days: 9)
    let (ending, outputs) = M.transition(.file(ready), .watchEnding)
    #expect(ending == .ending(ready, .sending))
    #expect(outputs == [.mark(episode: "fish-plush", kind: .found, ref: "ending")])

    let told = book(
      allClues + [named("crow"), found(0).with(ref: "ending")], allClues + [named("draft")],
      days: 9)
    let (again, none) = M.transition(.file(told), .watchEnding)
    #expect(again == .ending(told, .idle))
    #expect(none.isEmpty)
  }

  @Test func theFileCanAlwaysBeLeftAndNothingElseChangesIt() {
    let states: [M.State] = [
      .file(book()), .clue(book(), beat: 0, .idle), .naming(book(), choice: nil, .idle),
      .ending(book(), .idle),
    ]
    for state in states {
      #expect(M.transition(state, .dismissed).0 == .closed(book()))
    }
    #expect(M.transition(.clue(book(), beat: 0, .idle), .back).0 == .file(book()))
  }

  @Test func disablingClosesEverything() {
    for state: M.State in [.loading(episode, .first), .closed(book()), .file(book())] {
      #expect(M.transition(state, .disabled) == (.unavailable, []))
    }
  }

  @Test func refreshReadsTheRoomWithoutChangingTheScreen() {
    let state = M.State.clue(book(), beat: 0, .idle)
    #expect(M.transition(state, .refresh) == (state, [.fetch]))
    let marks = M.Marks(mine: [], partner: [found(0)])
    let (next, _) = M.transition(state, .fetched(marks, at: now))
    #expect(next == .clue(book([], [found(0)]), beat: 0, .idle))
  }

  /// Events that must change nothing, from states that cannot take them.
  @Test func rejectedEventsChangeNothing() {
    let unavailable = M.State.unavailable
    let loading = M.State.loading(episode, .first)
    let closed = M.State.closed(book())
    let file = M.State.file(book())
    let rejected: [(M.State, M.Event)] = [
      (unavailable, .opened), (unavailable, .refresh), (unavailable, .found),
      (unavailable, .fetched(.init(mine: [], partner: []), at: now)), (unavailable, .markFailed),
      (loading, .opened), (loading, .found), (loading, .enabled(episode, .second)),
      (closed, .found), (closed, .lookCloser(beat: 0)), (closed, .confirmName),
      (closed, .watchEnding), (closed, .dismissed), (closed, .markFailed),
      (file, .opened), (file, .found), (file, .confirmName), (file, .choose("crow")),
      (file, .back), (file, .markFailed), (file, .watchEnding),
      (.ending(book(), .idle), .opened), (.ending(book(), .idle), .found),
      (.naming(book(), choice: nil, .idle), .lookCloser(beat: 0)),
    ]
    for (state, event) in rejected {
      let (next, outputs) = M.transition(state, event)
      #expect(next == state, "\(state) \(event)")
      #expect(outputs.isEmpty, "\(state) \(event)")
    }
  }

  @Test func aLateAnswerIsKeptOnAClosedCase() {
    let marks = M.Marks(mine: [found(0)], partner: [])
    let (next, _) = M.transition(.closed(book()), .marked(marks, at: now))
    #expect(next == .closed(book([found(0)])))
  }
}

extension CaseMark {
  fileprivate func with(ref: String) -> CaseMark {
    CaseMark(episode: episode, kind: kind, ref: ref, at: at)
  }
}
