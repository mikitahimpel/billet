import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct CatReflexTests {
  @Test func aFullBlinkShutsTheEyeAsTheClipsDo() {
    #expect(CatReflexSystem.eyeScale(blink: 0) == 1)
    #expect(abs(CatReflexSystem.eyeScale(blink: 1) - CatReflexComponent.shut) < 1e-6)
    #expect(CatReflexSystem.eyeScale(blink: 3) == CatReflexSystem.eyeScale(blink: 1))
  }

  @Test func theBreathIsSubtleAndScalesWithStrength() {
    #expect(CatReflexSystem.chestSwell(breath: 0, strength: 1) == 1)
    let top = CatReflexSystem.chestSwell(breath: 0.5, strength: 1)
    #expect(top > 1 && top < 1.02)
    #expect(CatReflexSystem.chestSwell(breath: 0.5, strength: 0) == 1)
  }

  @Test func aFlickSwingsOutAndBackAndDies() {
    #expect(CatReflexSystem.flickSwing(clock: 0) == 0)
    let out = CatReflexSystem.flickSwing(clock: 0.15)
    let back = CatReflexSystem.flickSwing(clock: 0.45)
    #expect(out > 0.5 && back < 0)
    #expect(abs(CatReflexSystem.flickSwing(clock: 3)) < 0.05)
  }

  @MainActor @Test func onAndOffEasesRatherThanSnaps() throws {
    var reflex = try #require(
      CatReflexComponent(joints: ["root", "root/head", "root/head/eye_R", "root/head/ear_R"]))
    reflex.blinkGoal = 1
    CatReflexSystem.ease(&reflex, delta: 1 / 60)
    #expect(reflex.blink > 0.2 && reflex.blink < 0.6)
    for _ in 0..<9 { CatReflexSystem.ease(&reflex, delta: 1 / 60) }
    #expect(reflex.blink > 0.95, "shut within a sixth of a second")
    #expect(reflex.ancestors[3] == [0, 1])
  }

  /// With no clip re-posing the joints between frames, a held blink stays one blink deep.
  @MainActor @Test func aHeldReflexDoesNotPileUp() async throws {
    let cat = try #require(await NookiAssets.compiledCat(.detailed))
    _ = try #require(CatRig(model: cat, clips: CatCatalog.clips(.detailed)))
    let skinned = try #require(CatRig.firstSkinned(in: cat))
    var reflex = try #require(skinned.components[CatReflexComponent.self])
    let eye = try #require(reflex.eyes.first)
    let open = skinned.jointTransforms[eye].scale
    reflex.blink = 1
    reflex.breath = 0.5
    reflex.strength = 1
    for _ in 0..<5 { CatReflexSystem.apply(&reflex, to: skinned) }
    let once = skinned.jointTransforms[eye].scale
    #expect(abs(once.z / open.z - CatReflexComponent.shut) < 1e-4)
    reflex.blink = 0
    reflex.strength = 0
    CatReflexSystem.apply(&reflex, to: skinned)
    #expect(simd_length(skinned.jointTransforms[eye].scale - open) < 1e-5, "back to the clip's eye")
  }

  @MainActor @Test func everyDetailedCatHasTheReflexJoints() async throws {
    for model in [CatModel.detailed, .detailedKitten, .detailedFluffy, .hero] {
      let cat = try #require(await NookiAssets.compiledCat(model), "\(model)")
      let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)), "\(model)")
      #expect(rig.hasReflexes, "\(model)")
      let skinned = try #require(CatRig.firstSkinned(in: cat))
      let reflex = try #require(skinned.components[CatReflexComponent.self])
      #expect(reflex.eyes.count == 2 && reflex.ears.count == 2 && reflex.tail.count == 3)
      #expect(reflex.chest != nil)
    }
  }
}

#if os(macOS)
  /// The hero's face and tail with each reflex at full, for checking the axes by eye. Runs only
  /// when `CAT_REFLEX_SHOTS` names a folder to write into.
  @MainActor
  @Suite struct CatReflexShots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAT_REFLEX_SHOTS"] != nil))
    func eachReflexAtFull() async throws {
      let folder = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CAT_REFLEX_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let cases: [(String, (inout CatReflexComponent) -> Void)] = [
        ("none", { _ in }),
        ("blink", { $0.blink = 1 }),
        ("ear", { $0.ear = 1 }),
        (
          "flick",
          {
            $0.flick = 1
            $0.flickClock = 0.15
          }
        ),
        (
          "breath",
          {
            $0.breath = 0.5
            $0.strength = 8
          }
        ),
      ]
      for (name, set) in cases {
        let cat = try #require(await NookiAssets.compiledCat(.hero))
        _ = try #require(CatRig(model: cat, clips: CatCatalog.clips(.hero)))
        let skinned = try #require(CatRig.firstSkinned(in: cat))
        var reflex = try #require(skinned.components[CatReflexComponent.self])
        reflex.strength = 1
        set(&reflex)
        CatReflexSystem.apply(&reflex, to: skinned)
        // Nothing plays, so nothing would reset the joints for the system's next frames.
        skinned.components.remove(CatReflexComponent.self)
        let root = Entity()
        root.addChild(cat)
        let bounds = cat.visualBounds(relativeTo: nil)
        let renderer = try RealityRenderer()
        renderer.entities.append(root)
        for from: SIMD3<Float> in [[1, 2, -2], [-2, 1, -1], [0, 2, 2]] {
          let sun = Entity()
          sun.components.set(DirectionalLightComponent(color: .white, intensity: 5000))
          sun.look(at: .zero, from: from, relativeTo: nil)
          renderer.entities.append(sun)
        }
        let lens = PerspectiveCamera()
        lens.camera.fieldOfViewInDegrees = 35
        renderer.entities.append(lens)
        renderer.activeCamera = lens
        let size = simd_length(bounds.extents)
        lens.look(
          at: bounds.center, from: bounds.center + SIMD3(0.55, 0.35, -0.75) * size, relativeTo: nil)
        let image = try await GenzRenderShots.render(renderer, width: 600, height: 600)
        try GenzRenderShots.write(image, to: folder.appendingPathComponent("reflex-\(name).png"))
      }
    }
  }
#endif
