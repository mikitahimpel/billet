import Pet
import PetScene
import Testing

@testable import PetSceneReality

@Suite("NookiTouch")
struct NookiTouchTests {
  private let world = PetWorld(activity: .sleeping, delivery: 3)

  @Test func tappingMochiReportsThePet() {
    #expect(
      NookiTouch.of(.mochi, world: world, noteIsOpen: false)
        == NookiTouch(reaction: .wakeAndHop, event: .petted))
  }

  @Test func theLampStaysInsideTheScene() {
    #expect(
      NookiTouch.of(.lamp, world: world, noteIsOpen: false)
        == NookiTouch(reaction: .toggleLamp))
  }

  @Test func openingTheNoteReportsItsDeliveryAndClosingDoesNot() {
    #expect(
      NookiTouch.of(.note, world: world, noteIsOpen: false)
        == NookiTouch(reaction: .toggleNote, event: .noteOpened(delivery: 3)))
    #expect(
      NookiTouch.of(.note, world: world, noteIsOpen: true)
        == NookiTouch(reaction: .toggleNote))
  }

  @Test(arguments: [NookiTarget.plant, .bookcase, .bed, .yarn])
  func objectsOnlyWobble(target: NookiTarget) {
    #expect(
      NookiTouch.of(target, world: world, noteIsOpen: false)
        == NookiTouch(reaction: .wobble(target)))
  }

  @Test func noTouchDrivesTheDeliveryScenario() {
    for target in NookiTarget.allCases {
      let touch = NookiTouch.of(target, world: world, noteIsOpen: false)
      #expect(touch.event.flatMap { PetMachine.Event($0) } == nil)
    }
  }

  @Test func secondTapInsideTheWindowIsADoubleTap() {
    var timer = NookiTapTimer()
    let results = [10, 10.2].map { timer.isDoubleTap(at: $0) }
    #expect(results == [false, true])
  }

  @Test func slowTapsAndAThirdTapStayApart() {
    var timer = NookiTapTimer()
    let results = [10, 11, 11.1, 11.2].map { timer.isDoubleTap(at: $0) }
    #expect(results == [false, false, true, false])
  }

  @Test func bowlFillsWithEachPartnersTreat() {
    #expect(PetPlayState.Treat.neither.bowlFill == 0)
    #expect(PetPlayState.Treat.waitingOnPartner.bowlFill == 0.5)
    #expect(PetPlayState.Treat.waitingOnMe.bowlFill == 0.5)
    #expect(PetPlayState.Treat.fed.bowlFill == 1)
  }
}
