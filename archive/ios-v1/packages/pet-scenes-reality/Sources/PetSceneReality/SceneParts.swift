import CoreGraphics
import RealityKit

/// Small helpers that every stage uses on its entities: walking a tree, making an entity
/// tappable, and the warm ambient light.
@MainActor
enum SceneParts {
  /// Calls `body` on `entity` and on everything under it.
  static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
    body(entity)
    for child in entity.children { visit(child, body) }
  }

  /// Gives `entity` a box of `size`, centred on `center`, that taps and drags land on.
  static func makeTappable(_ entity: Entity, size: SIMD3<Float>, center: SIMD3<Float>) {
    entity.components.set(
      CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: center)]))
    entity.components.set(InputTargetComponent())
  }

  /// A warm ambient light, bright above like a ceiling in lamplight.
  static func ambientEnvironment() async -> EnvironmentResource? {
    guard let image = ambientGradient() else { return nil }
    return try? await EnvironmentResource(equirectangular: image)
  }

  private static func ambientGradient() -> CGImage? {
    let ceiling = CGColor(red: 1, green: 0.84, blue: 0.66, alpha: 1)
    let bounce = CGColor(red: 0.5, green: 0.34, blue: 0.28, alpha: 1)
    guard
      let context = CGContext(
        data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [ceiling, bounce] as CFArray,
        locations: [0, 1])
    else { return nil }
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 32), end: .zero, options: [])
    return context.makeImage()
  }
}
