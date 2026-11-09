import RoomInterface
import Testing

struct QuietRoomMachineTests {
  typealias M = QuietRoomMachine

  @Test func allowedStartsAWait() {
    #expect(M.transition(.off(wait: 0), .allowed(true)) == (.awake(wait: 1), [.wait(1)]))
  }

  @Test func theCurrentWaitMakesItQuiet() {
    #expect(M.transition(.awake(wait: 3), .waited(3)) == (.quiet(wait: 3), []))
    #expect(M.State.quiet(wait: 3).isQuiet)
  }

  @Test(arguments: [M.State.awake(wait: 3), .quiet(wait: 3)])
  func aTouchWakesAndWaitsAgain(state: M.State) {
    #expect(M.transition(state, .touched) == (.awake(wait: 4), [.wait(4)]))
  }

  @Test(arguments: [M.State.awake(wait: 3), .quiet(wait: 3)])
  func disallowedTurnsItOff(state: M.State) {
    #expect(M.transition(state, .allowed(false)) == (.off(wait: 3), []))
    #expect(!M.State.off(wait: 3).isQuiet)
  }

  /// A late wait, a repeated `allowed`, and anything while off change nothing.
  @Test(arguments: [
    (M.State.awake(wait: 3), M.Event.waited(2)),
    (.awake(wait: 3), .allowed(true)),
    (.quiet(wait: 3), .allowed(true)),
    (.quiet(wait: 3), .waited(3)),
    (.off(wait: 3), .allowed(false)),
    (.off(wait: 3), .touched),
    (.off(wait: 3), .waited(3)),
  ])
  func rejected(state: M.State, event: M.Event) {
    #expect(M.transition(state, event) == (state, []))
  }

  @Test func aWaitAfterATouchIsStale() {
    var (state, _) = M.transition(.off(wait: 0), .allowed(true))
    (state, _) = M.transition(state, .touched)
    (state, _) = M.transition(state, .waited(1))
    #expect(state == .awake(wait: 2))
    (state, _) = M.transition(state, .waited(2))
    #expect(state == .quiet(wait: 2))
  }

  @Test func onlyHideLetsTheFirstTouchThrough() {
    #expect(QuietChrome.hide.quietOpacity == 0)
    #expect(!QuietChrome.hide.quietTakesTouches)
    #expect(QuietChrome.dim.quietTakesTouches)
    #expect(QuietChrome.off.quietOpacity == 1)
  }
}

struct PartnerNoticeMachineTests {
  typealias M = PartnerNoticeMachine

  @Test(arguments: [M.State.away, .unnoticed])
  func anArrivalOnScreenIsNoticed(state: M.State) {
    #expect(M.transition(state, .input(partnerHere: true, visible: true)) == (.noticed, [.notice]))
  }

  @Test func anArrivalUnderACoverWaitsForTheRoom() {
    var (state, outputs) = M.transition(.away, .input(partnerHere: true, visible: false))
    #expect(state == .unnoticed && outputs.isEmpty)
    (state, outputs) = M.transition(state, .input(partnerHere: true, visible: true))
    #expect(state == .noticed && outputs == [.notice])
  }

  @Test(arguments: [true, false])
  func noticedOnceWhileTheyStay(visible: Bool) {
    #expect(M.transition(.noticed, .input(partnerHere: true, visible: visible)) == (.noticed, []))
  }

  @Test(arguments: [M.State.away, .unnoticed, .noticed], [true, false])
  func leavingResets(state: M.State, visible: Bool) {
    #expect(M.transition(state, .input(partnerHere: false, visible: visible)) == (.away, []))
  }
}
