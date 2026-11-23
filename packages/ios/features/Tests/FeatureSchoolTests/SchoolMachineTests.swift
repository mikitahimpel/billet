import Foundation
import SchoolInterface
import Testing

@testable import FeatureSchool

@Suite struct SchoolMachineTests {
  typealias M = SchoolMachine
  private let at = Date(timeIntervalSince1970: 100)

  private var book: SchoolBook {
    SchoolBook(skills: [
      .spin: TrickSkill(trick: .spin, stars: 1, teacher: "me"),
      .jump: TrickSkill(trick: .jump, stars: 3, teacher: "them"),
    ])
  }
  private var take: RoutineTake {
    RoutineTake(steps: [.spin, .jump, .spin].map { .init(trick: $0, landed: true) }, at: at)
  }
  private func ready(_ screen: M.Screen, saving: M.Saving = .idle, book: SchoolBook? = nil)
    -> M.State
  {
    .ready(M.Desk(book: book ?? self.book, screen: screen, saving: saving))
  }
  private func hit(_ plan: LessonPlan) -> Double {
    let window = plan.rounds[0].windows[0]
    return (window.lowerBound + window.upperBound) / 2
  }

  @Test func enablingLoadsTheSchoolAndDisablingDropsIt() {
    let (loading, outputs) = M.transition(.unavailable, .enabled)
    #expect(loading == .loading)
    #expect(outputs == [.fetch])
    #expect(M.transition(.loading, .fetched(book)).0 == ready(.closed))
    #expect(M.transition(.loading, .disabled).0 == .unavailable)
    #expect(M.transition(ready(.list), .disabled).0 == .unavailable)
    #expect(M.transition(ready(.list), .enabled).0 == ready(.list))
  }

  @Test func openingShowsTheListAndReadsAgainAndClosingKeepsWhatIsBeingSaved() {
    let (open, outputs) = M.transition(ready(.closed), .opened)
    #expect(open == ready(.list))
    #expect(outputs == [.fetch])
    #expect(M.transition(open, .opened).1 == [])
    let saving = ready(.list, saving: .saving(.spin, star: 2))
    #expect(M.transition(saving, .dismissed).0 == ready(.closed, saving: .saving(.spin, star: 2)))
    #expect(!ready(.closed).isOpen)
    #expect(open.isOpen)
  }

  @Test func backLeavesALessonARoutineOrAReplayForTheList() {
    let lesson = M.Screen.lesson(LessonMachine.start(LessonPlan(trick: .spin, star: 2)))
    for screen in [lesson, .routine(.picking([])), .watching(take)] {
      #expect(M.transition(ready(screen), .back).0 == ready(.list))
    }
    #expect(M.transition(ready(.list), .back).0 == ready(.list))
    #expect(M.transition(ready(.closed), .back).0 == ready(.closed))
  }

  @Test func askingForAKnownTrickRollsAgainstItsStars() {
    let (_, landed) = M.transition(ready(.list), .ask(.spin, roll: 0.1))
    #expect(landed == [.perform(.trick(.spin)), .count(.spin)])
    let (_, flubbed) = M.transition(ready(.list), .ask(.spin, roll: 0.9))
    #expect(flubbed == [.perform(.flub(SchoolFlub(turn: 900)))])
    #expect(M.transition(ready(.list), .ask(.jump, roll: 0.99)).1.contains(.count(.jump)))
    #expect(M.transition(ready(.list), .ask(.bow, roll: 0)).1 == [])
    #expect(M.transition(ready(.closed), .ask(.spin, roll: 0)).1 == [])
  }

  @Test func teachingStartsALessonForTheNextStarOnly() {
    let (state, _) = M.transition(ready(.list), .teach(.spin, seed: 3))
    #expect(
      state == ready(.lesson(LessonMachine.start(LessonPlan(trick: .spin, star: 2, seed: 3)))))
    #expect(M.transition(ready(.list), .teach(.jump, seed: 3)).0 == ready(.list))
    let first = M.transition(ready(.list), .teach(.bow, seed: 3)).0
    #expect(
      first.desk?.screen == .lesson(LessonMachine.start(LessonPlan(trick: .bow, star: 1, seed: 3))))
    let busy = ready(.list, saving: .failed(.spin, star: 2))
    #expect(M.transition(busy, .teach(.bow, seed: 3)).0 == busy)
  }

  @Test func aPassedLessonSendsItsStarOnceAndTheAnswerUpdatesTheBook() {
    let plan = LessonPlan(trick: .jump, star: 1)
    var state = ready(.lesson(LessonMachine.start(plan)), book: SchoolBook())
    var outputs: [M.Output] = []
    for _ in 0..<3 {
      let (judged, performed) = M.transition(state, .lesson(.tapped(hit(plan))))
      #expect(performed == [.perform(.trick(.jump))])
      (state, outputs) = M.transition(judged, .lesson(.next))
    }
    #expect(outputs == [.teach(.jump, star: 1)])
    #expect(state.desk?.saving == .saving(.jump, star: 1))
    #expect(M.transition(state, .lesson(.next)).1 == [])

    let failed = M.transition(state, .saveFailed).0
    #expect(failed.desk?.saving == .failed(.jump, star: 1))
    let (retried, again) = M.transition(failed, .retrySave)
    #expect(again == [.teach(.jump, star: 1)])
    let saved = M.transition(retried, .saved(book)).0
    #expect(saved.desk?.saving == .idle)
    #expect(saved.desk?.book == book)
  }

  @Test func savingEventsOutOfPlaceChangeNothing() {
    #expect(M.transition(ready(.list), .saveFailed).0 == ready(.list))
    #expect(M.transition(ready(.list), .retrySave).1 == [])
    let saving = ready(.list, saving: .saving(.spin, star: 2))
    #expect(M.transition(saving, .retrySave).1 == [])
  }

  @Test func aRoutineIsBuiltFromKnownTricksTriedAndSent() {
    #expect(M.transition(ready(.list, book: SchoolBook()), .buildRoutine).0.desk?.screen == .list)
    var state = M.transition(ready(.list), .buildRoutine).0
    #expect(state == ready(.routine(.picking([]))))
    state = M.transition(state, .routine(.pick(.bow))).0
    #expect(state == ready(.routine(.picking([]))))
    for trick in [SchoolTrick.spin, .jump, .spin] {
      state = M.transition(state, .routine(.pick(trick))).0
    }
    let stars: [SchoolTrick: Int] = [.spin: 1, .jump: 3]
    let (tried, played) = M.transition(
      state, .routine(.tryIt(rolls: [0, 0, 0], stars: stars, at: at)))
    #expect(tried == ready(.routine(.tried(take))))
    #expect(played == [.play(take.moves)])
    let (sending, sent) = M.transition(tried, .routine(.send))
    #expect(sent == [.send(take)])
    var after = book
    after.mine = take
    #expect(
      M.transition(sending, .routineSent(after)).0 == ready(.routine(.sent(take)), book: after))
    #expect(M.transition(sending, .routine(.sendFailed)).0 == ready(.routine(.failed(take))))
  }

  @Test func aRoutineAnswerAfterTheScreenIsLeftStillUpdatesTheBook() {
    var after = book
    after.mine = take
    #expect(M.transition(ready(.list), .routineSent(after)).0 == ready(.list, book: after))
    #expect(M.transition(ready(.list), .routine(.pick(.spin))).0 == ready(.list))
  }

  @Test func thePartnersRoutinePlaysAsItWent() {
    var with = book
    with.partner = take
    let (state, outputs) = M.transition(ready(.list, book: with), .watchPartner)
    #expect(state == ready(.watching(take), book: with))
    #expect(outputs == [.play(take.moves)])
    #expect(M.transition(ready(.list), .watchPartner).1 == [])
    #expect(M.transition(ready(.closed, book: with), .watchPartner).1 == [])
  }

  @Test func aReadRefreshesTheBookUnderAnyScreen() {
    #expect(
      M.transition(ready(.watching(take)), .fetched(SchoolBook())).0
        == ready(.watching(take), book: SchoolBook()))
    #expect(M.transition(ready(.list), .refresh).1 == [.fetch])
    #expect(M.transition(.loading, .refresh).1 == [.fetch])
  }

  @Test(arguments: [
    M.Event.disabled, .fetched(SchoolBook()), .refresh, .opened, .dismissed, .back,
    .ask(.spin, roll: 0), .teach(.spin, seed: 0), .lesson(.next), .saved(SchoolBook()),
    .saveFailed, .retrySave, .buildRoutine, .routine(.send), .routineSent(SchoolBook()),
    .watchPartner,
  ])
  func withNoSchoolNothingHappens(event: M.Event) {
    let (state, outputs) = M.transition(.unavailable, event)
    #expect(state == .unavailable)
    #expect(outputs == [])
  }

  @Test(arguments: [
    M.Event.enabled, .opened, .dismissed, .back, .ask(.spin, roll: 0), .teach(.spin, seed: 0),
    .lesson(.next), .saved(SchoolBook()), .saveFailed, .retrySave, .buildRoutine,
    .routine(.send), .routineSent(SchoolBook()), .watchPartner,
  ])
  func whileLoadingTheSheetCannotBeUsed(event: M.Event) {
    let (state, outputs) = M.transition(.loading, event)
    #expect(state == .loading)
    #expect(outputs == [])
  }
}
