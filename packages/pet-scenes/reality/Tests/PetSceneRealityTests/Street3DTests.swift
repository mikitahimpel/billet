import Foundation
import Pet
import RealityKit
import Testing
import simd

@testable import PetSceneReality

@MainActor
struct Street3DTests {
  @Test func theStreetLoadsWithinItsBudget() async throws {
    let assets = try #require(await Street3D.assets())
    // The whole view: at most 20k triangles, two textures, and no light of its own.
    #expect(assets.triangles <= 20_000)
    #expect(assets.atlas.width <= 1024 && assets.atlas.height <= 1024)
    let street = Street3D(assets: assets)
    var models = 0
    var lights = 0
    SceneParts.visit(street.root) { entity in
      if entity.components.has(ModelComponent.self) { models += 1 }
      if entity.components.has(PointLightComponent.self)
        || entity.components.has(SpotLightComponent.self)
        || entity.components.has(DirectionalLightComponent.self)
      {
        lights += 1
      }
    }
    // The street, the car and the cards, with the portal not yet fitted.
    #expect(models == 3)
    #expect(lights == 0)
  }

  @Test func theStreetHasASkyRightRoundWithinTheFarPlane() async throws {
    let assets = try #require(await Street3D.assets())
    // In the street's frame: x right, y up, minus z out through the window.
    let sky = assets.cards.bounds
    // It reaches well up and far out to either side, so any orbit looks into sky, not black.
    #expect(sky.max.y >= 200)
    #expect(sky.min.x <= -420 && sky.max.x >= 420)
    #expect(sky.min.z <= -239)
    // And what is seen of it up to a little above the horizon stays inside the room camera's far plane, with
    // room for the camera standing back from the window.
    let positions = assets.cards.contents.models.flatMap {
      $0.parts.flatMap { $0.positions.elements }
    }
    let reach = positions.filter { $0.y <= 60 }.map {
      simd_length(SIMD2($0.x, $0.z))
    }
    #expect(try #require(reach.max()) + 40 < GenzRoom.farClip)
  }

  @Test func theStreetIsSeenStraightOnFromTheCameraAtHome() {
    let origin = SIMD3<Float>(3.8, 3.15, -0.35)
    let eye = SIMD3<Float>(10.2, 9.8, 19.2)
    let frame = Street3D.frame(origin: origin, eye: eye)
    let right = SIMD3(frame.columns.0.x, frame.columns.0.y, frame.columns.0.z)
    let up = SIMD3(frame.columns.1.x, frame.columns.1.y, frame.columns.1.z)
    let back = SIMD3(frame.columns.2.x, frame.columns.2.y, frame.columns.2.z)
    // Straight out from the street's frame is straight away from the eye, through the window.
    #expect(simd_distance(-back, simd_normalize(origin - eye)) < 1e-4)
    #expect(abs(simd_dot(right, up)) < 1e-4)
    #expect(abs(simd_length(right) - 1) < 1e-4)
    // Its right stays level, so the street never leans as it turns.
    #expect(abs(right.y) < 1e-4)
    #expect(up.y > 0)
  }

  @Test func thePassingCarIsOnlyThereDuringAPass() async throws {
    let assets = try #require(await Street3D.assets())
    let street = Street3D(assets: assets)
    var seen = (on: false, off: false)
    for step in 0..<400 {
      let now = Double(step) * 0.5
      street.update(now: now, reduceMotion: false)
      let passing = SuburbNight.cars.pass(at: now) != nil
      #expect(street.isCarShown == passing)
      if passing { seen.on = true } else { seen.off = true }
    }
    #expect(seen.on && seen.off)
    street.update(now: 0, reduceMotion: true)
    #expect(!street.isCarShown)
  }

  @Test func theMeshFileRefusesSomethingElse() {
    #expect(throws: StreetMeshFile.Failure.self) { try StreetMeshFile(Data("nope".utf8)) }
  }

  @Test func theMeshFileTurnsItsImageRowsIntoRealityKitsUp() throws {
    var data = Data("BSV1".utf8)
    func put<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
    put(UInt32(1))
    data.append(4)
    data.append(contentsOf: Array("road".utf8))
    put(UInt32(3))
    put(UInt32(3))
    for (u, v) in [(0.25, 0.1), (0.5, 0.2), (0.75, 0.9)] as [(Float, Float)] {
      for value in [0, 0, 0, u, v] as [Float] { put(value) }
    }
    for index in [0, 1, 2] as [UInt16] { put(index) }
    let part = try #require(try StreetMeshFile(data).parts["road"])
    // A point near the image's top is near the top of RealityKit's texture too.
    let expected: [SIMD2<Float>] = [[0.25, 0.9], [0.5, 0.8], [0.75, 0.1]]
    #expect(zip(part.uvs, expected).allSatisfy { simd_distance($0, $1) < 1e-6 })
    #expect(part.indices == [0, 1, 2])
  }
}
