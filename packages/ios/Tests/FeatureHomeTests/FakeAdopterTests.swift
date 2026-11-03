import Foundation
import Pet
import Testing

@testable import FeatureHome

@Suite struct FakeAdopterTests {
  @Test func agreeingItPicksYourCatAfterAShortWhile() {
    var adopter = FakeAdopter(roll: { 0.1 })
    #expect(
      adopter.answer(.pick(.ginger)) == [
        FakeAdopter.Reply(after: FakeAdopter.pickDelay, move: .pick(.ginger))
      ])
  }

  @Test func disagreeingItPicksAnotherCatThenComesRound() {
    var adopter = FakeAdopter(roll: { 0.9 })
    let replies = adopter.answer(.pick(.ginger))
    #expect(replies.count == 2)
    guard case .pick(let first?) = replies.first?.move else {
      Issue.record("no first pick")
      return
    }
    #expect(first != .ginger)
    #expect(
      replies.last
        == FakeAdopter.Reply(
          after: FakeAdopter.pickDelay + FakeAdopter.comeRoundDelay, move: .pick(.ginger)))
  }

  @Test func afterItsFirstPickItFollowsYourChange() {
    var adopter = FakeAdopter(roll: { 0.9 })
    _ = adopter.answer(.pick(.ginger))
    #expect(
      adopter.answer(.pick(.kitten)) == [
        FakeAdopter.Reply(after: FakeAdopter.pickDelay, move: .pick(.kitten))
      ])
  }

  @Test func itHoldsWhenYouHoldLongEnoughToFillItsRing() {
    var adopter = FakeAdopter(roll: { 0.1 })
    let replies = adopter.answer(.hold(true))
    #expect(replies.map(\.move) == [.hold(true), .hold(false)])
    let held = replies[1].after - replies[0].after
    #expect(held > .milliseconds(Int(JointCatChoice.holdLength * 1000)))
  }

  @Test func liftingClearingAndAdoptingNeedNoAnswer() {
    var adopter = FakeAdopter()
    #expect(adopter.answer(.hold(false)).isEmpty)
    #expect(adopter.answer(.pick(nil)).isEmpty)
    #expect(adopter.answer(.adopt(.black)).isEmpty)
  }

  @Test func playedAgainstTheMachineItEndsInAnAdoption() {
    for roll in [0.1, 0.9] {
      var adopter = FakeAdopter(roll: { roll })
      var choice = JointCatChoice()
      var now = Date(timeIntervalSinceReferenceDate: 0)
      var pending: [(Date, AdoptionMove)] = []
      func send(_ moves: [AdoptionMove]) {
        for move in moves {
          for reply in adopter.answer(move) {
            pending.append((now.addingTimeInterval(reply.after.seconds), reply.move))
          }
        }
      }
      send(choice.pick(.fluffy))
      while choice.adopted == nil, now.timeIntervalSinceReferenceDate < 60 {
        now = now.addingTimeInterval(0.1)
        let due = pending.filter { $0.0 <= now }
        pending.removeAll { $0.0 <= now }
        for (_, move) in due { send(choice.received(move, at: now)) }
        if choice.agreed != nil, !choice.isHolding, !choice.iHeldOnce {
          send(choice.hold(true, at: now))
        }
        if choice.isHolding, choice.myRing(at: now) >= 1 { send(choice.hold(false, at: now)) }
        send(choice.tick(at: now))
      }
      #expect(choice.adopted == .fluffy, "roll \(roll)")
    }
  }
}

extension Duration {
  fileprivate var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
