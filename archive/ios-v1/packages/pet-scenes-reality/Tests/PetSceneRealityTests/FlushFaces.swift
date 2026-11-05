import Foundation
import RealityKit
import simd

@testable import PetSceneReality

/// Finds faces of different colours that lie in one plane and overlap, facing the same way, where
/// the camera can see them. Such faces fight for the same pixels and flicker as the camera moves.
@MainActor
enum FlushFaces {
  /// Two faces that share a plane.
  struct Clash: CustomStringConvertible {
    var first: String
    var second: String
    var normal: SIMD3<Float>
    var at: SIMD3<Float>

    var description: String {
      "\(first) and \(second) facing \(rounded(normal)) near \(rounded(at))"
    }

    private func rounded(_ value: SIMD3<Float>) -> String {
      String(format: "(%.2f, %.2f, %.2f)", value.x, value.y, value.z)
    }
  }

  private struct Face {
    var corners: [SIMD3<Float>]
    var normal: SIMD3<Float>
    var offset: Float
    var colour: String
    var owner: String
  }

  /// Faces closer than this, in scene units, count as one plane.
  static let tolerance: Float = 0.004
  /// Faces smaller than this, in square scene units, cover under a point at the rooms' camera
  /// distances, too little to show a flicker, such as the facets of a fairy-light bulb.
  static let smallest: Float = 0.0004

  /// The clashes among every model under `roots`, seen from any of `eyes`. Models for which
  /// `skip` is true, and everything under them, are left out.
  static func clashes(
    under roots: [Entity], seenFrom eyes: [SIMD3<Float>], skip: (Entity) -> Bool = { _ in false }
  ) -> [Clash] {
    var faces: [Face] = []
    for root in roots { collect(root, eyes: eyes, skip: skip, into: &faces) }
    var buckets: [SIMD3<Int32>: [Int]] = [:]
    for (index, face) in faces.enumerated() {
      buckets[SIMD3<Int32>((face.normal * 20).rounded(.toNearestOrEven)), default: []].append(index)
    }
    var clashes: [Clash] = []
    var seen = Set<String>()
    for indices in buckets.values {
      let sorted = indices.sorted { faces[$0].offset < faces[$1].offset }
      for (position, index) in sorted.enumerated() {
        let face = faces[index]
        for other in sorted[(position + 1)...] {
          let next = faces[other]
          // Normals a little apart give offsets a little apart, so the sort only narrows the
          // search; the faces count as one plane when each lies on the other's.
          guard next.offset - face.offset < 0.1 else { break }
          guard next.colour != face.colour, simd_dot(face.normal, next.normal) > 0.9995,
            distance(of: next, from: face) < tolerance, distance(of: face, from: next) < tolerance,
            overlap(face, next)
          else { continue }
          let pair = [face.owner + face.colour, next.owner + next.colour].sorted()
            .joined(separator: "|")
          guard seen.insert(pair).inserted else { continue }
          let centre = face.corners.reduce(.zero, +) / Float(face.corners.count)
          clashes.append(
            Clash(
              first: "\(face.owner) \(face.colour)", second: "\(next.owner) \(next.colour)",
              normal: face.normal, at: centre))
        }
      }
    }
    return clashes
  }

  private static func collect(
    _ entity: Entity, eyes: [SIMD3<Float>], skip: (Entity) -> Bool, into faces: inout [Face]
  ) {
    guard !skip(entity) else { return }
    if let model = entity as? ModelEntity, let component = model.model {
      let world = model.transformMatrix(relativeTo: nil)
      let owner = name(of: model)
      for instance in component.mesh.contents.instances {
        let transform = world * instance.transform
        guard let mesh = component.mesh.contents.models[instance.model] else { continue }
        for part in mesh.parts {
          let colour =
            component.materials.indices.contains(part.materialIndex)
            ? key(component.materials[part.materialIndex]) : "none"
          let points = part.positions.elements.map { point in
            let moved = transform * SIMD4(point, 1)
            return SIMD3(moved.x, moved.y, moved.z)
          }
          let indices = part.triangleIndices?.elements ?? []
          for start in stride(from: 0, to: indices.count - 2, by: 3) {
            let corners = (0..<3).map { points[Int(indices[start + $0])] }
            let cross = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
            guard simd_length(cross) / 2 > smallest else { continue }
            let normal = simd_normalize(cross)
            let centre = (corners[0] + corners[1] + corners[2]) / 3
            guard eyes.contains(where: { simd_dot($0 - centre, normal) > 0 }) else { continue }
            faces.append(
              Face(
                corners: corners, normal: normal, offset: simd_dot(normal, corners[0]),
                colour: colour, owner: owner))
          }
        }
      }
    }
    for child in entity.children { collect(child, eyes: eyes, skip: skip, into: &faces) }
  }

  /// How far the furthest corner of `face` lies from the plane of `other`.
  private static func distance(of face: Face, from other: Face) -> Float {
    face.corners.map { abs(simd_dot(other.normal, $0) - other.offset) }.max() ?? 0
  }

  /// Whether two faces in one plane cover a shared area, more than touching along an edge.
  private static func overlap(_ first: Face, _ second: Face) -> Bool {
    let normal = first.normal
    let axis = abs(normal.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
    let across = simd_normalize(simd_cross(normal, axis))
    let up = simd_cross(normal, across)
    let flat = { (point: SIMD3<Float>) in SIMD2(simd_dot(point, across), simd_dot(point, up)) }
    let one = first.corners.map(flat)
    let two = second.corners.map(flat)
    for shape in [one, two] {
      for index in shape.indices {
        let edge = shape[(index + 1) % shape.count] - shape[index]
        let side = SIMD2(-edge.y, edge.x)
        let a = one.map { simd_dot($0, side) }
        let b = two.map { simd_dot($0, side) }
        let margin = simd_length(side) * 1e-3
        if a.max()! <= b.min()! + margin || b.max()! <= a.min()! + margin { return false }
      }
    }
    return true
  }

  private static func key(_ material: any RealityKit.Material) -> String {
    if let lit = material as? PhysicallyBasedMaterial {
      return "lit \(lit.baseColor.tint) \(lit.baseColor.texture != nil)"
    }
    if let unlit = material as? UnlitMaterial {
      return "unlit \(unlit.color.tint) \(unlit.color.texture != nil) \(unlit.blending)"
    }
    return "\(type(of: material))"
  }

  private static func name(of entity: Entity) -> String {
    var names: [String] = []
    var current: Entity? = entity
    while let found = current, names.count < 3 {
      if !found.name.isEmpty { names.append(found.name) }
      current = found.parent
    }
    let mesh = (entity as? ModelEntity)?.model?.mesh.contents.models.first?.id ?? "?"
    return names.isEmpty ? mesh : "\(names.joined(separator: "<")) [\(mesh)]"
  }
}
