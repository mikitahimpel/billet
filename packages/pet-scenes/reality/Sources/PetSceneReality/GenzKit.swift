import CoreGraphics
import Foundation
import RealityKit

/// Flat-shaded low-poly meshes and plain materials for the styled rooms, made in code and shared:
/// a mesh or a material asked for twice is built once.
///
/// Positions are in room units with y up. Every face has its own normals, so light falls on each
/// facet evenly and the pieces read as faceted rather than smooth.
@MainActor
final class GenzKit {
  private var meshes: [String: MeshResource] = [:]
  private var materials: [GenzColour: PhysicallyBasedMaterial] = [:]
  private var glows: [GlowKey: UnlitMaterial] = [:]

  private struct GlowKey: Hashable {
    let colour: GenzColour
    let opacity: Float
  }

  nonisolated init() {}

  // MARK: - Meshes

  /// A box of `size`, centred on the origin.
  func box(_ size: SIMD3<Float>) -> MeshResource {
    cached("box \(size)") { .generateBox(size: size) }
  }

  /// A plane of `width` by `height` facing +z, centred on the origin.
  func plane(width: Float, height: Float) -> MeshResource {
    cached("plane \(width) \(height)") { .generatePlane(width: width, height: height) }
  }

  /// A faceted cylinder or cone standing on y = 0: `sides` flat faces, `radius` at the bottom and
  /// `top` at the top, closed at both ends.
  func prism(sides: Int, radius: Float, top: Float, height: Float, turn: Float = 0.3)
    -> MeshResource
  {
    cached("prism \(sides) \(radius) \(top) \(height) \(turn)") {
      var faces = GenzFaces()
      let ring = (0..<sides).map { index -> SIMD2<Float> in
        let angle = turn + Float(index) * 2 * .pi / Float(sides)
        return SIMD2(cos(angle), sin(angle))
      }
      for index in 0..<sides {
        let a = ring[index]
        let b = ring[(index + 1) % sides]
        faces.quad(
          SIMD3(a.x * radius, 0, a.y * radius), SIMD3(a.x * top, height, a.y * top),
          SIMD3(b.x * top, height, b.y * top), SIMD3(b.x * radius, 0, b.y * radius))
      }
      faces.fan(ring.reversed().map { SIMD3($0.x * top, height, $0.y * top) })
      faces.fan(ring.map { SIMD3($0.x * radius, 0, $0.y * radius) })
      return faces.mesh()
    }
  }

  /// `outline` in the x-y plane, given depth along z and centred on z = 0. The outline runs
  /// anticlockwise seen from +z and must be convex.
  func slab(_ name: String, outline: [SIMD2<Float>], depth: Float) -> MeshResource {
    cached("slab \(name) \(depth)") {
      var faces = GenzFaces()
      let front = outline.map { SIMD3($0.x, $0.y, depth / 2) }
      let back = outline.map { SIMD3($0.x, $0.y, -depth / 2) }
      faces.fan(front)
      faces.fan(back.reversed())
      for index in outline.indices {
        let next = (index + 1) % outline.count
        faces.quad(front[index], back[index], back[next], front[next])
      }
      return faces.mesh()
    }
  }

  /// Many boxes as one mesh, for a pattern of the same colour such as half a checkered rug.
  func boxes(_ name: String, _ parts: [(centre: SIMD3<Float>, size: SIMD3<Float>)]) -> MeshResource
  {
    cached("boxes \(name)") {
      var faces = GenzFaces()
      for part in parts { faces.box(centre: part.centre, size: part.size) }
      return faces.mesh()
    }
  }

  func cached(_ key: String, make: () -> MeshResource) -> MeshResource {
    if let mesh = meshes[key] { return mesh }
    let mesh = make()
    meshes[key] = mesh
    return mesh
  }

  /// How many meshes have been built, for checks that pieces share them.
  var meshCount: Int { meshes.count }

  // MARK: - Materials

  /// A matte material in `colour`.
  func matte(_ colour: GenzColour) -> PhysicallyBasedMaterial {
    if let material = materials[colour] { return material }
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: colour.platformColour)
    material.roughness = 0.9
    material.metallic = 0.0
    materials[colour] = material
    return material
  }

  /// A material that shows `colour` whatever the light, for lamps, screens and LED strips.
  func glow(_ colour: GenzColour, opacity: Float = 1) -> UnlitMaterial {
    let key = GlowKey(colour: colour, opacity: opacity)
    if let material = glows[key] { return material }
    var material = UnlitMaterial(color: colour.platformColour)
    if opacity < 1 { material.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
    glows[key] = material
    return material
  }

  /// One part of a piece.
  func part(
    _ mesh: MeshResource, _ material: any RealityKit.Material, at position: SIMD3<Float> = .zero,
    turn: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
  ) -> ModelEntity {
    let model = ModelEntity(mesh: mesh, materials: [material])
    model.position = position
    model.orientation = turn
    return model
  }

  /// A box in the mockups' terms: its near corner at (`x`, `y`, `z`) with `x` along the back wall,
  /// `y` out from it and `z` up, measuring `w` by `d` by `h`.
  func block(
    _ x: Float, _ y: Float, _ z: Float, _ w: Float, _ d: Float, _ h: Float,
    _ material: any RealityKit.Material
  ) -> ModelEntity {
    part(box([w, h, d]), material, at: GenzRoomPoint(x + w / 2, y + d / 2, z + h / 2).scene)
  }
}

/// A point in the mockups' room coordinates: `x` along the back wall, `y` out from the back wall
/// towards the viewer, `z` up. The scene's y is up and z points out of the back wall.
struct GenzRoomPoint: Equatable {
  var x: Float
  var y: Float
  var z: Float

  init(_ x: Float, _ y: Float, _ z: Float) {
    self.x = x
    self.y = y
    self.z = z
  }

  var scene: SIMD3<Float> { SIMD3(x, z, y) }
}

/// An sRGB colour, from the mockups' hex values.
struct GenzColour: Hashable, Sendable {
  let red: Float
  let green: Float
  let blue: Float

  init(_ hex: UInt32) {
    red = Float((hex >> 16) & 0xFF) / 255
    green = Float((hex >> 8) & 0xFF) / 255
    blue = Float(hex & 0xFF) / 255
  }

  var cgColor: CGColor {
    CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
  }

  var platformColour: RealityKit.Material.Color {
    RealityKit.Material.Color(
      red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
  }
}

/// Triangles with a normal per face, collected into one mesh.
struct GenzFaces {
  private var positions: [SIMD3<Float>] = []
  private var normals: [SIMD3<Float>] = []
  private var indices: [UInt32] = []

  /// A flat polygon from its corners, wound anticlockwise seen from the side it faces.
  mutating func fan(_ corners: [SIMD3<Float>]) {
    guard corners.count >= 3 else { return }
    let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
    let start = UInt32(positions.count)
    positions += corners
    normals += Array(repeating: normal, count: corners.count)
    for index in 1..<(corners.count - 1) {
      indices += [start, start + UInt32(index), start + UInt32(index + 1)]
    }
  }

  mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
    fan([a, b, c, d])
  }

  mutating func box(centre: SIMD3<Float>, size: SIMD3<Float>) {
    let h = size / 2
    func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { centre + SIMD3(x, y, z) * h }
    quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1))
    quad(p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1))
    quad(p(1, -1, 1), p(1, -1, -1), p(1, 1, -1), p(1, 1, 1))
    quad(p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1))
    quad(p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), p(-1, 1, -1))
    quad(p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1))
  }

  var triangleCount: Int { indices.count / 3 }

  @MainActor func mesh() -> MeshResource {
    var descriptor = MeshDescriptor(name: "genz")
    descriptor.positions = MeshBuffer(positions)
    descriptor.normals = MeshBuffer(normals)
    descriptor.primitives = .triangles(indices)
    return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: 0.01)
  }
}
