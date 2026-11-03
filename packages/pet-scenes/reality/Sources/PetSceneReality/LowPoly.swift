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

  /// A round piece turned about the vertical axis, as on a lathe: `profile` runs from the bottom
  /// middle up the outside to the top middle, each point a radius and a height. Normals follow the
  /// profile, so it shades smooth; a point given twice in a row makes a crisp edge there.
  static func lathe(_ name: String, profile: [SIMD2<Float>], segments: Int = 32) -> MeshResource {
    cached("lathe \(name) \(segments)") {
      let normals2D = profile.indices.map { index -> SIMD2<Float> in
        let point = profile[index]
        let before = index > 0 && profile[index - 1] != point ? profile[index - 1] : point
        let after =
          index < profile.count - 1 && profile[index + 1] != point ? profile[index + 1] : point
        let along = after - before
        let normal = SIMD2(along.y, -along.x)
        return simd_length(normal) > 0 ? simd_normalize(normal) : [0, 1]
      }
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var indices: [UInt32] = []
      for (point, normal) in zip(profile, normals2D) {
        for segment in 0...segments {
          let around = Float(segment) / Float(segments) * 2 * .pi
          positions.append([point.x * cos(around), point.y, point.x * sin(around)])
          normals.append([normal.x * cos(around), normal.y, normal.x * sin(around)])
        }
      }
      let width = UInt32(segments + 1)
      for ring in 0..<UInt32(profile.count - 1) {
        for segment in 0..<UInt32(segments) {
          let a = ring * width + segment
          let b = a + width
          indices += [a, b, a + 1, a + 1, b, b + 1]
        }
      }
      return mesh(positions, normals, indices)
    }
  }

  /// A box of `size` centred on the origin with its edges and corners rounded to `radius`, each
  /// quarter round in `steps`: the flat faces stay flat and the rounds shade smooth.
  static func roundedBox(_ size: SIMD3<Float>, radius: Float, steps: Int = 3) -> MeshResource {
    cached("rounded box \(size) \(radius) \(steps)") {
      let radius = min(radius, size.min() / 2)
      let inner = size / 2 - radius
      let quarters: [(x: Float, z: Float)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var indices: [UInt32] = []
      // Rows from the top down, each half of the height twice at the middle; columns around,
      // each quarter's ends twice, so the flat faces lie between the repeated rows and columns.
      for half in 0..<2 {
        for row in 0...steps {
          let polar = (Float(half) + Float(row) / Float(steps)) * .pi / 2
          for (quarter, signs) in quarters.enumerated() {
            for column in 0...steps {
              let around = (Float(quarter) + Float(column) / Float(steps)) * .pi / 2
              let normal = SIMD3(sin(polar) * cos(around), cos(polar), sin(polar) * sin(around))
              let corner = SIMD3(signs.x, half == 0 ? 1 : -1, signs.z) * inner
              normals.append(normal)
              positions.append(corner + normal * radius)
            }
          }
        }
      }
      let width = UInt32(4 * (steps + 1))
      let rows = UInt32(2 * (steps + 1))
      for row in 0..<(rows - 1) {
        for column in 0..<width {
          let a = row * width + column
          let next = row * width + (column + 1) % width
          let b = a + width
          let bNext = next + width
          indices += [a, next, b, next, bNext, b]
        }
      }
      // The flat top and bottom between the four corners.
      let corners = (0..<4).map { UInt32($0 * (steps + 1)) }
      let bottom = (rows - 1) * width
      indices += [corners[0], corners[2], corners[1], corners[0], corners[3], corners[2]]
      indices += [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]].map {
        $0 + bottom
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
