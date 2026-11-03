import Foundation
import RealityKit

/// Smooth spheres and cylinders with a few hundred triangles, made once per size.
///
/// RealityKit's own `generateSphere` has 8,064 triangles and its rounded boxes over 13,000, far
/// more than a toy a few centimetres across needs on a phone screen.
@MainActor
enum LowPoly {
  private static var meshes: [String: MeshResource] = [:]

  /// A sphere of `radius`, centred on the origin, `segments` around and half as many up.
  static func sphere(radius: Float, segments: Int = 16) -> MeshResource {
    cached("sphere \(radius) \(segments)") {
      let rings = max(segments / 2, 3)
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var indices: [UInt32] = []
      for ring in 0...rings {
        let polar = Float(ring) / Float(rings) * .pi
        for segment in 0...segments {
          let around = Float(segment) / Float(segments) * 2 * .pi
          let normal = SIMD3(sin(polar) * cos(around), cos(polar), sin(polar) * sin(around))
          normals.append(normal)
          positions.append(normal * radius)
        }
      }
      let width = UInt32(segments + 1)
      for ring in 0..<UInt32(rings) {
        for segment in 0..<UInt32(segments) {
          let a = ring * width + segment
          let b = a + width
          indices += [a, a + 1, b, a + 1, b + 1, b]
        }
      }
      return mesh(positions, normals, indices)
    }
  }

  /// A closed cylinder of `height` standing centred on the origin, as `generateCylinder` is.
  static func cylinder(height: Float, radius: Float, segments: Int = 20) -> MeshResource {
    cached("cylinder \(height) \(radius) \(segments)") {
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var indices: [UInt32] = []
      let half = height / 2
      for segment in 0...segments {
        let around = Float(segment) / Float(segments) * 2 * .pi
        let side = SIMD3(cos(around), 0, sin(around))
        positions += [side * radius + [0, -half, 0], side * radius + [0, half, 0]]
        normals += [side, side]
      }
      for segment in 0..<UInt32(segments) {
        let a = segment * 2
        indices += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
      }
      for (y, up) in [(half, Float(1)), (-half, Float(-1))] {
        let centre = UInt32(positions.count)
        positions.append([0, y, 0])
        normals.append([0, up, 0])
        for segment in 0...segments {
          let around = Float(segment) / Float(segments) * 2 * .pi
          positions.append([cos(around) * radius, y, sin(around) * radius])
          normals.append([0, up, 0])
        }
        for segment in 0..<UInt32(segments) {
          let a = centre + 1 + segment
          indices += up > 0 ? [centre, a + 1, a] : [centre, a, a + 1]
        }
      }
      return mesh(positions, normals, indices)
    }
  }

  private static func cached(_ key: String, make: () -> MeshResource) -> MeshResource {
    if let mesh = meshes[key] { return mesh }
    let mesh = make()
    meshes[key] = mesh
    return mesh
  }

  private static func mesh(
    _ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], _ indices: [UInt32]
  ) -> MeshResource {
    var descriptor = MeshDescriptor(name: "low-poly")
    descriptor.positions = MeshBuffer(positions)
    descriptor.normals = MeshBuffer(normals)
    descriptor.primitives = .triangles(indices)
    return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: 0.01)
  }
}
