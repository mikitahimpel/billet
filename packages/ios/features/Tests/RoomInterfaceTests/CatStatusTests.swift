import Pet
import RoomInterface
import Testing

struct CatStatusTests {
  @Test func needsAreRoundedToTwentieths() throws {
    let status = CatStatus(
      rounding: PetNeeds(full: 0.512, rested: 0.49, loved: 0.0, playful: 1.0), mind: nil)
    let needs = try #require(status.needs)
    #expect(needs.full == 0.5)
    #expect(needs.rested == 0.5)
    #expect(needs.loved == 0)
    #expect(needs.playful == 1)
  }

  @Test func driftWithinAStepIsTheSameStatus() {
    let a = CatStatus(rounding: PetNeeds(all: 0.52), mind: .none)
    let b = CatStatus(rounding: PetNeeds(all: 0.51), mind: .none)
    #expect(a == b)
    #expect(a != CatStatus(rounding: PetNeeds(all: 0.58), mind: .none))
  }

  @Test func noNeedsStaysNil() {
    #expect(CatStatus(rounding: nil, mind: nil) == CatStatus())
  }
}
