import Pet
import RealityKit
import simd

/// The cat's needs as things in the room: a bowl beside its place whose food sinks as Full
/// falls, and a ball of yarn that comes out when it wants to play. The bowl is always there to be
/// filled with a tap; the yarn shows only while the variant is on and the room has no toy yarn.
@MainActor
final class GenzLifeProps {
  let root = Entity()
  private let food: ModelEntity
  private let yarn: ModelEntity
  private let foodHeight: Float
  let bowl: Entity
  private var needs: PetNeeds?
  /// How full a meal the person put down has left the bowl, overriding the needs while it lasts.
  private var meal: Float?
  /// Whether the room has a yarn of its own to play with, so this one stays away.
  var roomHasYarn = false

  /// At most what a finished meal leaves in the bowl, a quarter.
  static let leftover: Float = 0.3

  /// When Playful is below this, the yarn lies out, waiting.
  static let yarnBelow = 0.5

  init(kit: GenzKit, catLength length: Float) {
    let radius = length * 0.26
    let height = length * 0.11
    foodHeight = height * 0.8
    let bowl = ModelEntity(
      mesh: LowPoly.cylinder(height: height, radius: radius),
      materials: [kit.matte(GenzColour(0xA5442B))])
    bowl.position.y = height / 2
    food = ModelEntity(
      mesh: LowPoly.cylinder(height: foodHeight, radius: radius * 0.82),
      materials: [kit.matte(GenzColour(0x8A5422))])
    yarn = ModelEntity(
      mesh: LowPoly.sphere(radius: length * 0.09),
      materials: [kit.matte(GenzColour(0xD06A43))])
    let bowlHolder = Entity()
    bowlHolder.name = "genz-bowl"
    bowlHolder.position = [length * 0.75, 0, length * 0.25]
    bowlHolder.addChild(bowl)
    bowlHolder.addChild(food)
    yarn.position = [-length * 0.7, length * 0.09, length * 0.45]
    root.addChild(bowlHolder)
    root.addChild(yarn)
    self.bowl = bowlHolder
    apply()
  }

  /// Places the props around the cat's spot, turned with it.
  func place(at spot: SIMD3<Float>, heading: Float) {
    root.position = spot
    root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
  }

  func show(_ needs: PetNeeds?) {
    self.needs = needs
    apply()
  }

  /// Shows a meal put down as `level` of a full bowl, or nil to go back to showing the needs.
  func show(meal level: Float?) {
    meal = level
    apply()
  }

  private func apply() {
    // What is left of a meal shows until the cat is hungry again, then the bowl is empty.
    if let left = meal, left <= Self.leftover, let needs, needs.full < LifeConfig.standard.lowBelow
    {
      meal = nil
    }
    let fromNeeds = needs.map { Float(max(0.04, min(1, ($0.full - 0.2) / 0.8))) }
    let fill = meal ?? fromNeeds ?? 0.04
    food.scale = [1, max(fill, 0.04), 1]
    food.position.y = foodHeight * max(fill, 0.04) / 2 + 0.002
    yarn.isEnabled = !roomHasYarn && (needs.map { $0.playful < Self.yarnBelow } ?? false)
  }

  /// How much warmer the lamp burns for how loved the cat feels: none at the floor, a little
  /// more as Loved fills.
  static func warmth(_ needs: PetNeeds?) -> Float {
    guard let needs else { return 0 }
    return Float(max(0, min(1, (needs.loved - 0.3) / 0.6))) * 0.35
  }
}
