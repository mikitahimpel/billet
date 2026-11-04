import Pet
import Testing

@Suite("PetSpecies")
struct PetSpeciesTests {
  @Test func everyModelIsACatWithABody() {
    for model in CatModel.allCases {
      #expect(model.species == .cat)
      let body = model.anatomy
      #expect(body.length > 0.2 && body.length < 0.4, "\(model)")
      #expect(body.head.x > 0 && body.head.y > body.tail.y, "\(model)")
      #expect(body.mouth.x > 0, "\(model)")
    }
  }

  @Test func theStandardCatHasTheMadeCatsBody() {
    #expect(CatChoice.standard.model.anatomy == .madeCat)
  }

  @Test func theHeroIsInLabsButNotTheDefault() {
    #expect(CatModel.allCases.contains(.hero))
    #expect(CatChoice.standard.model != .hero)
    #expect(CatModel.hero.coats == [.natural, .greyWhite, .black])
  }

  @Test func theHerosBigHeadHoldsANoteFurtherOut() {
    #expect(CatModel.hero.anatomy.mouth.x > PetAnatomy.madeCat.mouth.x)
    #expect(CatModel.hero.anatomy.length > PetAnatomy.madeCat.length)
  }
}
