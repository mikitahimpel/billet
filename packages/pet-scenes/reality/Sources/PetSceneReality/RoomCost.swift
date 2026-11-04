import Observation
import RealityKit

/// Parts of a room that a measuring run's `cost` script switches off one at a time, to see what
/// each one costs to draw. Nothing else changes it, so in an ordinary run every part shows.
@MainActor @Observable
final class RoomCostSwitches {
  static let shared = RoomCostSwitches()

  /// The flat layers over and around the room that are switched off.
  private(set) var off: Set<String> = []
  /// How to bring back each part of the 3D room that is switched off.
  @ObservationIgnored private var undo: [String: [() -> Void]] = [:]

  func shows(_ name: String) -> Bool { !off.contains(name) }

  /// The 3D parts: the lights' shadow maps, the lights, the see-through models and the cat.
  /// The flat ones: the layers drawn over the room, its haze, halos, colour grade and sky.
  static let names = [
    "shadows", "lights", "transparent", "cat", "layers", "haze", "halos", "grade", "sky",
    "frameCap",
  ]

  /// Switches `name` on or off in `root`; `all` switches every part.
  func set(_ name: String, isOn: Bool, root: Entity, cat: Entity) {
    if name == "all" {
      for each in Self.names { set(each, isOn: isOn, root: root, cat: cat) }
      return
    }
    if name == "frameCap" { FramePace.shared.setCapped(isOn) }
    if isOn {
      off.remove(name)
      for step in undo.removeValue(forKey: name) ?? [] { step() }
      return
    }
    guard !off.contains(name) else { return }
    off.insert(name)
    undo[name] = Self.switchOff(name, root: root, cat: cat)
  }

  private static func switchOff(_ name: String, root: Entity, cat: Entity) -> [() -> Void] {
    var steps: [() -> Void] = []
    func remove<Kind: Component>(_ kind: Kind.Type, from entity: Entity) {
      guard let component = entity.components[kind] else { return }
      entity.components.remove(kind)
      steps.append { entity.components.set(component) }
    }
    func hide(_ entity: Entity) {
      guard entity.isEnabled else { return }
      entity.isEnabled = false
      steps.append { entity.isEnabled = true }
    }
    switch name {
    case "shadows":
      for entity in everything(under: root) {
        remove(DirectionalLightComponent.Shadow.self, from: entity)
        remove(SpotLightComponent.Shadow.self, from: entity)
      }
    case "lights":
      for entity in everything(under: root) {
        remove(PointLightComponent.self, from: entity)
        remove(SpotLightComponent.self, from: entity)
        remove(DirectionalLightComponent.self, from: entity)
      }
    case "transparent":
      for entity in everything(under: root) where isSeeThrough(entity) { hide(entity) }
    case "cat":
      hide(cat)
    default:
      break
    }
    return steps
  }

  private static func everything(under root: Entity) -> [Entity] {
    var found: [Entity] = []
    var queue = [root]
    while let entity = queue.popLast() {
      found.append(entity)
      queue += entity.children
    }
    return found
  }

  /// Whether `entity` draws blended over what is behind it.
  private static func isSeeThrough(_ entity: Entity) -> Bool {
    if let opacity = entity.components[OpacityComponent.self]?.opacity, opacity < 1 { return true }
    guard let model = entity.components[ModelComponent.self] else { return false }
    return model.materials.contains { material in
      if let pbr = material as? PhysicallyBasedMaterial, case .transparent = pbr.blending {
        return true
      }
      if let unlit = material as? UnlitMaterial, case .transparent = unlit.blending { return true }
      return false
    }
  }
}
