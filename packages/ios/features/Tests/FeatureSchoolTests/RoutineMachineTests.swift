import Foundation
import SchoolInterface
import Testing

@testable import FeatureSchool

@Suite struct RoutineMachineTests {
  typealias M = RoutineMachine
  private let at = Date(timeIntervalSince1970: 100)
  private let stars: [SchoolTrick: Int] = [.spin: 3, .jump: 1]
  private var take: RoutineTake {
    RoutineTake(
      steps: [
        .init(trick: .spin, landed: true), .init(trick: .jump, landed: false),
        .init(trick: .spin, landed: true),
      ], at: at)
  }

  @Test func picksAddUpToFiveAndComeOffTheEnd() {
    var state = M.State.picking([])
    for _ in 0..<7 { state = M.transition(state, .pick(.spin)).0 }
    #expect(state.picks.count == 5)
    state = M.transition(state, .removeLast).0
    #expect(state.picks.count == 4)
    #expect(M.transition(.picking([]), .removeLast).0 == .picking([]))
  }

  @Test func aTryNeedsThreeToFivePicksAndOneRollEach() {
    let short = M.State.picking([.spin, .jump])
    #expect(M.transition(short, .tryIt(rolls: [0, 0], stars: stars, at: at)).0 == short)
    let three = M.State.picking([.spin, .jump, .spin])
    #expect(M.transition(three, .tryIt(rolls: [0], stars: stars, at: at)).0 == three)
  }

  @Test func aTryRollsEachTrickAgainstItsStarsAndPlaysTheTake() {
    let (state, outputs) = M.transition(
      .picking([.spin, .jump, .spin]), .tryIt(rolls: [0.99, 0.5, 0], stars: stars, at: at))
    #expect(state == .tried(take))
    #expect(outputs == [.play(take.moves)])
  }

  @Test func aTrickWithNoStarsNeverLands() {
    let (state, _) = M.transition(
      .picking([.bow, .bow, .bow]), .tryIt(rolls: [0, 0, 0], stars: stars, at: at))
    #expect(
      state
        == .tried(
          RoutineTake(steps: [.bow, .bow, .bow].map { .init(trick: $0, landed: false) }, at: at)))
  }

  @Test func aTakeIsSentOnceAndAFailureKeepsItForAnotherSend() {
    let (sending, outputs) = M.transition(.tried(take), .send)
    #expect(sending == .sending(take))
    #expect(outputs == [.send(take)])
    #expect(M.transition(sending, .send).1 == [])
    #expect(M.transition(sending, .sent).0 == .sent(take))
    let failed = M.transition(sending, .sendFailed).0
    #expect(failed == .failed(take))
    #expect(M.transition(failed, .send).1 == [.send(take)])
  }

  @Test func againGoesBackToThePicksOfTheTake() {
    for state in [M.State.tried(take), .failed(take), .sent(take)] {
      #expect(M.transition(state, .again).0 == .picking([.spin, .jump, .spin]))
    }
    #expect(M.transition(.sending(take), .again).0 == .sending(take))
  }

  @Test func eventsOutOfPlaceChangeNothing() {
    let cases: [(M.State, M.Event)] = [
      (.picking([.spin]), .again), (.picking([.spin]), .send), (.picking([.spin]), .sent),
      (.picking([.spin]), .sendFailed), (.tried(take), .pick(.spin)), (.tried(take), .removeLast),
      (.tried(take), .tryIt(rolls: [0, 0, 0], stars: stars, at: at)), (.tried(take), .sent),
      (.tried(take), .sendFailed), (.sending(take), .pick(.spin)), (.sending(take), .removeLast),
      (.sending(take), .tryIt(rolls: [0, 0, 0], stars: stars, at: at)), (.sent(take), .pick(.spin)),
      (.sent(take), .removeLast), (.sent(take), .send), (.sent(take), .sent),
      (.sent(take), .sendFailed), (.sent(take), .tryIt(rolls: [0, 0, 0], stars: stars, at: at)),
      (.failed(take), .pick(.spin)), (.failed(take), .removeLast), (.failed(take), .sent),
      (.failed(take), .sendFailed),
      (.failed(take), .tryIt(rolls: [0, 0, 0], stars: stars, at: at)),
    ]
    for (state, event) in cases {
      let (next, outputs) = M.transition(state, event)
      #expect(next == state)
      #expect(outputs == [])
    }
  }
}
