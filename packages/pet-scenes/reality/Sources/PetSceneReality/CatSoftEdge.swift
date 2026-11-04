import Pet
import RealityKit

/// A soft edge for a furry mesh cat: a pale sheen on its coat, which RealityKit's physically based
/// material lights only at grazing angles, so the silhouette glows a little like fur against the
/// light instead of ending in a hard, plastic line. It is part of the cat's own material, so it
/// costs no extra draw and no extra geometry.
enum CatSoftEdge {
  /// How bright the sheen is: enough to soften the outline, not enough to pale the coat.
  static let sheen: Float = 0.5

  /// Gives `cat`'s coat the sheen when its model wants a soft edge.
  static func dress(_ cat: Entity, as model: CatModel) {
    guard model.softEdge else { return }
    let tint = PhysicallyBasedMaterial.SheenColor(tint: .init(white: CGFloat(sheen), alpha: 1))
    SceneParts.visit(cat) { node in
      guard var parts = node.components[ModelComponent.self] else { return }
      parts.materials = parts.materials.map { material in
        guard var physical = material as? PhysicallyBasedMaterial else { return material }
        physical.sheen = tint
        return physical
      }
      node.components.set(parts)
    }
  }
}

extension CatModel {
  /// Whether this cat's coat takes a soft, furry edge (see CatSoftEdge).
  var softEdge: Bool { self == .mochi }
}
