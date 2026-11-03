import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
struct LowPolyRoundTests {
  @Test func aRoundedBoxKeepsItsSize() {
    let size: SIMD3<Float> = [1.2, 0.3, 0.8]
    let bounds = LowPoly.roundedBox(size, radius: 0.05).bounds
    #expect(simd_length(bounds.extents - size) < 0.001)
    #expect(simd_length(bounds.center) < 0.001)
  }

  @Test func aRoundedBoxsNormalsPointOutOfIt() {
    var checked = 0
    for model in LowPoly.roundedBox([1, 1, 1], radius: 0.2).contents.models {
      for part in model.parts {
        let normals = part.normals?.elements ?? []
        #expect(normals.count == part.positions.elements.count)
        for (position, normal) in zip(part.positions.elements, normals) {
          #expect(simd_dot(position, normal) > 0)
          checked += 1
        }
      }
    }
    #expect(checked > 0)
  }

  @Test func aLatheIsAsWideAndTallAsItsProfile() {
    let bounds = LowPoly.lathe("test", profile: [[0, 0], [0.4, 0], [0.5, 0.5], [0, 1]]).bounds
    #expect(abs(bounds.extents.y - 1) < 0.001)
    #expect(abs(bounds.extents.x - 1) < 0.001)
  }

  @Test func theRoundThingsStayLight() {
    let cushion = LowPoly.lathe(
      "budget",
      profile: [
        [0, 0], [0.74, 0], [0.84, 0.04], [0.87, 0.13], [0.82, 0.22], [0.7, 0.27], [0, 0.28],
      ],
      segments: 48)
    var triangles = 0
    for model in cushion.contents.models {
      for part in model.parts { triangles += (part.triangleIndices?.count ?? 0) / 3 }
    }
    #expect(triangles < 1_000)
  }
}
