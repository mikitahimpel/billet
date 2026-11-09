import Pet
import RoomInterface
import Testing

struct CatStatusSpokenTests {
  @Test func beforeHerBrainRunsSheIsSettlingIn() {
    #expect(CatStatus().spoken == "Settling in")
  }

  @Test func metNeedsSayOnlyWhatSheDoes() {
    #expect(CatStatus(needs: PetNeeds(all: 0.9), mind: .napping).spoken == "Napping")
  }

  @Test(arguments: [
    (PetNeeds(full: 0.5, rested: 0.9, loved: 0.9, playful: 0.9), "Napping, a little hungry"),
    (PetNeeds(full: 0.2, rested: 0.9, loved: 0.9, playful: 0.9), "Napping, hungry"),
    (PetNeeds(full: 0.9, rested: 0.9, loved: 0.9, playful: 0.1), "Napping, bored"),
    (PetNeeds(full: 0.6, rested: 0.4, loved: 0.9, playful: 0.9), "Napping, a little sleepy"),
  ])
  func theLowestNeedIsNamed(needs: PetNeeds, spoken: String) {
    #expect(CatStatus(needs: needs, mind: .napping).spoken == spoken)
  }

  @Test func everyMindHasWords() {
    for mind in CatMind.allCases {
      #expect(!CatStatus(mind: mind).spoken.isEmpty)
    }
  }
}
