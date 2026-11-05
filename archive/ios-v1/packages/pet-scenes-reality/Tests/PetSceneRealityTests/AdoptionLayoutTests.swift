import Pet
import PetScene
import Testing

@testable import PetSceneReality

@Suite struct AdoptionLayoutTests {
  let cats = Array(repeating: CatChoice.standard, count: 5)

  @Test func fiveCushionsLeftToRight() {
    #expect(AdoptionLayout.cushions.count == 5)
    let xs = AdoptionLayout.cushions.map(\.x)
    #expect(xs == xs.sorted())
  }

  @Test func theAgreedCatComesHalfWayAndOthersStay() {
    let state = AdoptionSceneState(cats: cats, mine: 2, theirs: 2)
    #expect(AdoptionLayout.forward(state) == [0, 0, 0.55, 0, 0])
    #expect(AdoptionLayout.acts(state)[2] == .agreed)
  }

  @Test func aBidBringsBothCandidatesOutOnePlayingOneHeadbutting() {
    let state = AdoptionSceneState(cats: cats, mine: 3, theirs: 1)
    #expect(AdoptionLayout.forward(state) == [0, 1, 0, 1, 0])
    let acts = AdoptionLayout.acts(state)
    #expect(acts[1] == .bid(playful: true))
    #expect(acts[3] == .bid(playful: false))
    #expect(acts[0] == .sit)
  }

  @Test func onePickComesALittleForward() {
    let state = AdoptionSceneState(cats: cats, mine: 4)
    #expect(AdoptionLayout.forward(state) == [0, 0, 0, 0, 0.25])
  }

  @Test func onceAdoptedTheOthersSettleAndItWalksOut() {
    let adopted = AdoptionSceneState(cats: cats, adopted: 0, moment: .adopted)
    #expect(AdoptionLayout.acts(adopted) == [.greet, .settle, .settle, .settle, .settle])
    let leaving = AdoptionSceneState(cats: cats, adopted: 0, moment: .leaving)
    #expect(AdoptionLayout.acts(leaving)[0] == .walk)
  }

  @Test func theWayOutEndsDarkAtTheExit() {
    let end = AdoptionExit.spot(from: 2, at: AdoptionExit.length)
    #expect(end == GenzRoomPoint(AdoptionLayout.exit.x, AdoptionLayout.exit.y, 0))
    #expect(AdoptionExit.darkness(at: 0, reduceMotion: false) == 0)
    #expect(AdoptionExit.darkness(at: AdoptionExit.length, reduceMotion: false) == 1)
    #expect(!AdoptionExit.isDone(at: 1, reduceMotion: false))
    #expect(AdoptionExit.isDone(at: AdoptionExit.reducedLength, reduceMotion: true))
    #expect(AdoptionExit.flight(at: 0) == [0, 0, 1])
  }
}
