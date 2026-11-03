import Foundation
import Pet
import Testing

@testable import FeatureHome

@MainActor
@Suite struct AdoptionModelTests {
  final class Clock {
    var now = Date(timeIntervalSinceReferenceDate: 0)
  }

  @Test func picksTravelAndAdoptingKeepsTheCatOnce() {
    let clock = Clock()
    var sent: [AdoptionMove] = []
    var kept: [AdoptionCat] = []
    let model = AdoptionModel(
      send: { sent.append($0) }, adopt: { kept.append($0) }, clock: { clock.now })
    model.tapped(1)
    #expect(sent == [.pick(.greyWhite)])
    #expect(model.scene.mine == 1)

    model.received(.pick(.greyWhite))
    #expect(model.scene.agreed == 1)

    model.pressing(true)
    model.received(.hold(true))
    clock.now += 0.6
    model.tick()
    #expect(model.scene.myRing == 0.5)
    clock.now += 0.7
    model.tick()
    #expect(sent.last == .adopt(.greyWhite))
    #expect(kept == [.greyWhite])
    #expect(model.moment == .adopted)
    #expect(model.scene.adopted == 1)
    model.tick()
    model.received(.adopt(.greyWhite))
    #expect(kept == [.greyWhite])

    model.goHome()
    #expect(model.scene.moment == .leaving)
  }

  @Test func theirAdoptSettlesItHereToo() {
    var kept: [AdoptionCat] = []
    let model = AdoptionModel(send: { _ in }, adopt: { kept.append($0) })
    model.received(.adopt(.black))
    #expect(kept == [.black])
    #expect(model.moment == .adopted)
  }

  @Test func tapsAfterAdoptingAndBeforeChoosingDoNothing() {
    var sent: [AdoptionMove] = []
    let model = AdoptionModel(send: { sent.append($0) }, adopt: { _ in })
    model.tapped(99)
    #expect(sent.isEmpty)
    model.received(.adopt(.kitten))
    model.tapped(0)
    #expect(sent.isEmpty)
  }

  @Test func goingHomeWaitsForTheAdoption() {
    let model = AdoptionModel(send: { _ in }, adopt: { _ in })
    model.goHome()
    #expect(model.moment == .choosing)
  }
}
