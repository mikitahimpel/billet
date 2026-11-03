import Foundation
import Pet
import PetScene
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
struct AdoptionStageTests {
  @Test func aCatFadesOntoItsCushionAndEndsOpaque() async {
    let stage = AdoptionStage(kit: GenzKit(), cats: GenzCatSource())
    stage.setOnScreen(true)
    stage.begin(AdoptionSceneState(cats: [.standard]))
    stage.start()
    defer { stage.setOnScreen(false) }

    let deadline = ContinuousClock.now + .seconds(15)
    var seat: Entity? {
      stage.root.findEntity(named: AdoptionStage.catPrefix + "0")?.children
        .first { $0.name == AdoptionStage.seatName }
    }
    while seat?.children.isEmpty != false, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    guard let placed = seat, !placed.children.isEmpty else {
      Issue.record("the cat never arrived")
      return
    }

    var opacities: [Float] = []
    // Later than any frame the stage's own timer has fired, so every hand-fired step counts.
    var time = 1e9
    while placed.components.has(OpacityComponent.self), opacities.count < 120 {
      opacities.append(placed.components[OpacityComponent.self]?.opacity ?? 1)
      time += 1 / 60
      stage.frames.fire(at: time)
    }

    #expect(opacities.first ?? 1 < 0.2, "the cat popped in")
    #expect(opacities == opacities.sorted(), "the fade went backwards")
    #expect(!placed.components.has(OpacityComponent.self), "the cat stayed translucent")
    #expect(Double(opacities.count) / 60 < AdoptionStage.fadeLength + 0.1)
  }
}
