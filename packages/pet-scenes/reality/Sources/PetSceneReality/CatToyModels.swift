import CoreGraphics
import Pet
import RealityKit

/// The toys every room puts on the cat's floor, made from simple shapes so they need no
/// assets: a pale blue ball, a ball of yarn with a loose strand, a laser pointer with a red
/// tip, and a wand with a stick and a three-colour feather. Sizes follow the cat's length.
@MainActor
enum CatToyModels {
  static func make(length: Float) -> [CatToy: Entity] {
    func material(_ hex: UInt32, rough: Float = 0.7) -> SimpleMaterial {
      SimpleMaterial(
        color: .init(
          red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: 1),
        roughness: .float(rough), isMetallic: false)
    }

    let ball = ModelEntity(
      mesh: .generateSphere(radius: length * 0.07), materials: [material(0x7EC8E3, rough: 0.35)])
    let yarn = ModelEntity(
      mesh: .generateSphere(radius: length * 0.09), materials: [material(0xD9566B, rough: 0.95)])
    // A loose strand of yarn wound round it.
    let strand = ModelEntity(
      mesh: .generateBox(size: [length * 0.19, length * 0.012, length * 0.012]),
      materials: [material(0xF08A9B, rough: 0.95)])
    strand.orientation = simd_quatf(angle: 0.6, axis: [0, 0, 1])
    yarn.addChild(strand)

    let pen = ModelEntity(
      mesh: .generateBox(
        size: [length * 0.26, length * 0.045, length * 0.045], cornerRadius: 0.01),
      materials: [material(0x3B3F4A, rough: 0.4)])
    let tip = ModelEntity(
      mesh: .generateSphere(radius: length * 0.02),
      materials: [UnlitMaterial(color: .init(red: 1, green: 0.2, blue: 0.2, alpha: 1))])
    tip.position = [length * 0.135, 0, 0]
    pen.addChild(tip)

    let wand = Entity()
    let stick = ModelEntity(
      mesh: .generateBox(size: [length * 0.012, length * 0.012, length * 0.85]),
      materials: [material(0xC89B6D)])
    stick.position = [0, 0, length * 0.42]
    stick.name = "stick"
    wand.addChild(stick)
    let feather = Entity()
    feather.name = "feather"
    for (index, hex) in [UInt32(0xF4A6C6), 0xE76FA5, 0xFFD27A].enumerated() {
      let plume = ModelEntity(
        mesh: .generateSphere(radius: length * 0.045), materials: [material(hex, rough: 1)])
      plume.scale = [0.45, 0.35, 1.6]
      plume.orientation = simd_quatf(angle: Float(index - 1) * 0.45, axis: [0, 1, 0])
      plume.position = [Float(index - 1) * length * 0.02, 0, -length * 0.05]
      feather.addChild(plume)
    }
    wand.addChild(feather)

    return [.ball: ball, .yarn: yarn, .laser: pen, .wand: wand]
  }

  /// How far above the floor the toy's middle sits when it lies there.
  static func lift(_ toy: CatToy, length: Float) -> Float {
    switch toy {
    case .ball: length * 0.07
    case .yarn: length * 0.09
    case .laser: length * 0.023
    case .wand: length * 0.02
    }
  }

  /// The red dot a laser pointer makes on the floor.
  static func laserDot(length: Float) -> ModelEntity {
    let dot = ModelEntity(
      mesh: .generateCylinder(height: 0.002, radius: length * 0.06),
      materials: [UnlitMaterial(color: .init(red: 1, green: 0.12, blue: 0.12, alpha: 1))])
    dot.isEnabled = false
    return dot
  }
}
