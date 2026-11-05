import Foundation
import Testing

@testable import Pet

@Suite struct JointCatChoiceTests {
  let start = Date(timeIntervalSinceReferenceDate: 0)
  func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

  @Test func bothPickTheSameCatAndHoldTogether() {
    var choice = JointCatChoice()
    #expect(choice.pick(.ginger) == [.pick(.ginger)])
    #expect(choice.received(.pick(.ginger), at: at(0)) == [])
    #expect(choice.agreed == .ginger)
    #expect(choice.bid == nil)

    #expect(choice.hold(true, at: at(0)) == [.hold(true)])
    #expect(choice.received(.hold(true), at: at(0.5)) == [])
    #expect(choice.myRing(at: at(0.6)) == 0.5)
    #expect(choice.tick(at: at(1)) == [])
    #expect(choice.tick(at: at(2)) == [.adopt(.ginger)])
    #expect(choice.adopted == .ginger)
    #expect(choice.agreed == nil)
  }

  @Test func holdingOneAfterTheOtherAdoptsToo() {
    var choice = JointCatChoice()
    _ = choice.pick(.black)
    _ = choice.received(.pick(.black), at: at(0))
    _ = choice.hold(true, at: at(1))
    #expect(choice.hold(false, at: at(2.5)) == [.hold(false)])
    #expect(choice.iHeldOnce)
    #expect(choice.myRing(at: at(3)) == 1)
    _ = choice.received(.hold(true), at: at(10))
    #expect(choice.received(.hold(false), at: at(11.3)) == [.adopt(.black)])
    #expect(choice.adopted == .black)
  }

  @Test func aShortTapFillsNoRing() {
    var choice = JointCatChoice()
    _ = choice.pick(.kitten)
    _ = choice.received(.pick(.kitten), at: at(0))
    _ = choice.hold(true, at: at(1))
    _ = choice.hold(false, at: at(1.5))
    #expect(!choice.iHeldOnce)
    #expect(choice.myRing(at: at(2)) == 0)
  }

  @Test func differentPicksMakeABidAndHoldingDoesNothing() {
    var choice = JointCatChoice()
    _ = choice.pick(.fluffy)
    _ = choice.received(.pick(.kitten), at: at(0))
    #expect(choice.agreed == nil)
    #expect(choice.bid?.mine == .fluffy)
    #expect(choice.bid?.theirs == .kitten)
    #expect(choice.hold(true, at: at(1)) == [])
    #expect(!choice.isHolding)
    // No timer: a long while later it is still a bid.
    #expect(choice.tick(at: at(600)) == [])
    #expect(choice.adopted == nil)
  }

  @Test func changingYourMindLetsGoAndEmptiesTheRings() {
    var choice = JointCatChoice()
    _ = choice.pick(.ginger)
    _ = choice.received(.pick(.ginger), at: at(0))
    _ = choice.hold(true, at: at(1))
    _ = choice.hold(false, at: at(2.5))
    #expect(choice.iHeldOnce)
    _ = choice.hold(true, at: at(3))
    #expect(choice.pick(.black) == [.hold(false), .pick(.black)])
    #expect(!choice.iHeldOnce)
    #expect(!choice.isHolding)
    #expect(choice.bid?.mine == .black)

    // The partner comes round: the rings start again from empty.
    _ = choice.received(.pick(.black), at: at(4))
    #expect(choice.agreed == .black)
    #expect(choice.myRing(at: at(5)) == 0)
    #expect(choice.theirRing(at: at(5)) == 0)
  }

  @Test func thePartnerChangingTheirMindResetsTheirHold() {
    var choice = JointCatChoice()
    _ = choice.pick(.ginger)
    _ = choice.received(.pick(.ginger), at: at(0))
    _ = choice.received(.hold(true), at: at(1))
    _ = choice.received(.pick(.greyWhite), at: at(1.5))
    #expect(!choice.partnerIsHolding)
    #expect(choice.tick(at: at(5)) == [])
    #expect(!choice.theyHeldOnce)
  }

  @Test func thePartnerLeavingLiftsTheirFingerButKeepsTheirPick() {
    var choice = JointCatChoice()
    _ = choice.pick(.ginger)
    _ = choice.received(.pick(.ginger), at: at(0))
    _ = choice.received(.hold(true), at: at(1))
    choice.partnerPresence(false)
    #expect(!choice.partnerHere)
    #expect(!choice.partnerIsHolding)
    #expect(choice.theirs == .ginger)
    #expect(choice.tick(at: at(5)) == [])

    choice.partnerPresence(true)
    _ = choice.hold(true, at: at(6))
    _ = choice.received(.hold(true), at: at(6))
    #expect(choice.tick(at: at(7.3)) == [.adopt(.ginger)])
  }

  @Test func anAdoptFromThePartnerSettlesItAndLaterMovesChangeNothing() {
    var choice = JointCatChoice()
    _ = choice.pick(.ginger)
    #expect(choice.received(.adopt(.fluffy), at: at(0)) == [])
    #expect(choice.adopted == .fluffy)
    #expect(choice.mine == .fluffy)
    #expect(choice.pick(.black) == [])
    #expect(choice.hold(true, at: at(1)) == [])
    #expect(choice.received(.pick(.kitten), at: at(1)) == [])
    #expect(choice.received(.adopt(.black), at: at(1)) == [])
    #expect(choice.adopted == .fluffy)
  }

  @Test func pickingNothingClearsThePick() {
    var choice = JointCatChoice()
    _ = choice.pick(.ginger)
    #expect(choice.pick(nil) == [.pick(nil)])
    #expect(choice.mine == nil)
    #expect(choice.pick(nil) == [])
  }

  @Test func everyCatIsADetailedCat() {
    for cat in AdoptionCat.allCases {
      #expect([.detailed, .detailedKitten, .detailedFluffy].contains(cat.choice.model), "\(cat)")
    }
    #expect(Set(AdoptionCat.allCases.map(\.choice)).count == AdoptionCat.allCases.count)
  }
}
