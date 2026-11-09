import RoomInterface
import Testing

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
