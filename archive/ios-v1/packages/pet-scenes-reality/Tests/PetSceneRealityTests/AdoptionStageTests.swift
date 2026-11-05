import Foundation
import Pet
import PetScene
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
struct AdoptionStageTests {
  @Test func aCatFadesOntoItsCushionAndEndsOpaque() async {
    // The model is read from disk before the stage starts, held so the stage finds it loaded:
    // a busy runner can take a minute over that read, and how long it takes is not what this
    // test is about. It only reports the time.
    let cats = GenzCatSource()
    let holder = NSObject()
    cats.hold([.standard], for: holder)
    let loading = ContinuousClock.now
    guard await cats.cat(.standard) != nil else {
      Issue.record("the standard cat's model did not load")
      return
    }
    print("AdoptionStageTests: the cat's model loaded in \(ContinuousClock.now - loading)")

    let stage = AdoptionStage(kit: GenzKit(), cats: cats)
    stage.setOnScreen(true)
    stage.begin(AdoptionSceneState(cats: [.standard]))
    stage.start()
    defer {
      stage.setOnScreen(false)
      withExtendedLifetime(holder) {}
    }

    // With the model loaded, placing it takes a few frames; the ceiling is only for a stage that
    // never places it at all.
    let placing = ContinuousClock.now
    let deadline = placing + .seconds(120)
    var seat: Entity? {
      stage.root.findEntity(named: AdoptionStage.catPrefix + "0")?.children
        .first { $0.name == AdoptionStage.seatName }
    }
    while seat?.children.isEmpty != false, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    guard let placed = seat, !placed.children.isEmpty else {
      Issue.record("the cat was never placed, though its model had loaded")
      return
    }
    print("AdoptionStageTests: the cat was placed in \(ContinuousClock.now - placing)")

    var opacities: [Float] = []
    // Later than any frame the stage's own timer has fired, so every hand-fired step counts.
    var time = 1e9
    while placed.components.has(OpacityComponent.self), opacities.count < 120 {
      opacities.append(placed.components[OpacityComponent.self]?.opacity ?? 1)
      time += 1 / 60
      stage.frames.fire(at: time)
    }

    // The stage's own timer may have run part of the fade already; a cat that popped in would
    // have had no fade at all.
    #expect(!opacities.isEmpty && opacities[0] < 1, "the cat popped in")
    #expect(opacities == opacities.sorted(), "the fade went backwards")
    #expect(!placed.components.has(OpacityComponent.self), "the cat stayed translucent")
    #expect(Double(opacities.count) / 60 < AdoptionStage.fadeLength + 0.1)
  }
}
