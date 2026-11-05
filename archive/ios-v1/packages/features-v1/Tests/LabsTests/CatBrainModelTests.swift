import Foundation
import Pet
import Testing

@testable import Labs

@MainActor
@Suite struct CatBrainModelTests {
  private func life(at date: Date) -> PetLifeModel {
    PetLifeModel(
      me: "a", fallbackPartner: "b", defaults: UserDefaults(suiteName: "brain-\(UUID())")!,
      clock: { date })
  }

  @Test func aTickGivesAFrame() {
    let model = CatBrainModel(life: life(at: Date(timeIntervalSince1970: 1_793_700_000)))
    model.setSeed(CatBrainModel.seed(pair: "ROOM", cat: .standard))
    #expect(model.frame != nil)
  }

  @Test func theSeedIsThePairsAndTheCats() {
    let one = CatBrainModel.seed(pair: "ROOM", cat: .standard)
    #expect(one == CatBrainModel.seed(pair: "ROOM", cat: .standard))
    #expect(one != CatBrainModel.seed(pair: "OTHER", cat: .standard))
  }

  @Test func eventsReachTheBrain() {
    let life = life(at: Date(timeIntervalSince1970: 1_793_700_000))
    let model = CatBrainModel(life: life)
    model.setSeed(7)
    life.record(.note)
    model.tick()
    #expect(model.frame?.stack.step == .carryNote || model.frame?.stack.step == .wake)
  }

  @Test func touchShowsWithoutChangingTheBrain() {
    let model = CatBrainModel(life: life(at: Date(timeIntervalSince1970: 1_793_700_000)))
    model.setSeed(7)
    let step = model.frame?.stack.step
    model.setLive(.held)
    #expect(model.frame?.stack.interaction == .held)
    #expect(model.frame?.stack.step == step)
    #expect(model.frame?.action == .dangle)
  }
}
