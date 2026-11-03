import Pet
import RealityKit
import simd

/// The cat's needs as things in the room: a bowl beside its place whose food sinks as Full
/// falls, and a ball of yarn that comes out when it wants to play. Hidden while the variant is off.
@MainActor
final class GenzLifeProps {
  let root = Entity()
  private let food: ModelEntity
  private let yarn: ModelEntity
  private let foodHeight: Float

  /// When Playful is below this, the yarn lies out, waiting.
  static let yarnBelow = 0.5

  init(kit: GenzKit, catLength length: Float) {
    let radius = length * 0.2
    let height = length * 0.09
    foodHeight = height * 0.8
    let bowl = ModelEntity(
      mesh: .generateCylinder(height: height, radius: radius),
      materials: [kit.matte(GenzColour(0xA5442B))])
    bowl.position.y = height / 2
    food = ModelEntity(
      mesh: .generateCylinder(height: foodHeight, radius: radius * 0.82),
      materials: [kit.matte(GenzColour(0x8A5422))])
    yarn = ModelEntity(
      mesh: .generateSphere(radius: length * 0.09),
      materials: [kit.matte(GenzColour(0xD06A43))])
    let bowlHolder = Entity()
    bowlHolder.position = [length * 0.75, 0, length * 0.25]
    bowlHolder.addChild(bowl)
    bowlHolder.addChild(food)
    yarn.position = [-length * 0.7, length * 0.09, length * 0.45]
    root.addChild(bowlHolder)
    root.addChild(yarn)
    root.isEnabled = false
  }

  /// Places the props around the cat's spot, turned with it.
  func place(at spot: SIMD3<Float>, heading: Float) {
    root.position = spot
    root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
  }

  func show(_ needs: PetNeeds?) {
    guard let needs else {
      root.isEnabled = false
      return
    }
    root.isEnabled = true
    let fill = Float(max(0.04, min(1, (needs.full - 0.2) / 0.8)))
    food.scale = [1, fill, 1]
    food.position.y = foodHeight * fill / 2 + 0.002
    yarn.isEnabled = needs.playful < Self.yarnBelow
  }

  /// How much warmer the lamp burns for how loved the cat feels: none at the floor, a little
  /// more as Loved fills.
  static func warmth(_ needs: PetNeeds?) -> Float {
    guard let needs else { return 0 }
    return Float(max(0, min(1, (needs.loved - 0.3) / 0.6))) * 0.35
  }
}
