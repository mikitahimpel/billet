import Foundation
import Pet
import RealityKit

/// The lighting preset's rig in a tab scene, as ``GenzGlow`` and ``GenzRoom`` apply it in the
/// styled rooms: the scene's lamps as key lights, the ambient fill, a rim light behind its
/// character, a soft light in the middle of the room, a low sun, and soft contact shadows. With
/// the lighting off the scene keeps its own light.
@MainActor
final class TabLighting {
  /// One of the scene's own lamps, with the light it has before a preset changes it.
  private struct Key {
    let light: Entity
    let colour: GenzColour
    let intensity: Float
    let reach: Float
  }

  let root = Entity()
  private(set) var look = LightingLook.off
  private var keys: [Key] = []
  private var ambient: Entity?
  private var ownAmbient = (top: GenzColour(0xFFFFFF), bottom: GenzColour(0x808080))
  private var exponent: Float = 1
  private let rim = Entity()
  private let core = Entity()
  private let sun = Entity()
  private var shadows: [ModelEntity] = []
  private var reduceMotion = false
  private var clock = 0.0
  /// How far the scene's lights are up, from 0 (out) to 1, as while a scene fades in.
  private var dimmer: Float = 1

  init() {
    rim.components.set(
      SpotLightComponent(
        color: GenzColour(0xFFB86A).platformColour, intensity: 0, innerAngleInDegrees: 12,
        outerAngleInDegrees: 30, attenuationRadius: 10))
    core.components.set(PointLightComponent(color: .white, intensity: 0, attenuationRadius: 9))
    sun.components.set(DirectionalLightComponent(color: .white, intensity: 0))
    sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 16, depthBias: 2))
    sun.isEnabled = false
    for light in [rim, core, sun] { root.addChild(light) }
  }

  /// Lights everything under `room` with an ambient from `top` and `bottom`, which a preset's
  /// fill tints, and returns what lets anything added later take the same light.
  func ambient(_ room: Entity, top: GenzColour, bottom: GenzColour, exponent: Float)
    -> ImageBasedLightReceiverComponent?
  {
    ownAmbient = (top, bottom)
    self.exponent = exponent
    guard let environment = TabLook.ambient(top: top, bottom: bottom) else { return nil }
    let entity = Entity()
    entity.components.set(
      ImageBasedLightComponent(source: .single(environment), intensityExponent: exponent))
    room.addChild(entity)
    ambient = entity
    let receiver = ImageBasedLightReceiverComponent(imageBasedLight: entity)
    NookiDiorama.visit(room) { $0.components.set(receiver) }
    return receiver
  }

  /// A point light for one of the scene's lamps, which a preset recolours, brightens and softens.
  func key(_ colour: GenzColour, intensity: Float, reach: Float, at point: GenzRoomPoint) -> Entity
  {
    let light = TabLook.bulb(colour, intensity: intensity, reach: reach, at: point)
    keys.append(Key(light: light, colour: colour, intensity: intensity, reach: reach))
    return light
  }

  /// Aims the rim light at `target` from behind and above it.
  func rim(at target: SIMD3<Float>, from: SIMD3<Float>) {
    rim.look(at: target, from: from, relativeTo: nil)
  }

  /// Where the soft light in the middle of the room sits.
  func core(at point: SIMD3<Float>) {
    core.position = point
  }

  /// Where the low sun comes from.
  func sun(at target: SIMD3<Float>, from: SIMD3<Float>) {
    sun.look(at: target, from: from, relativeTo: nil)
  }

  /// A soft shadow lying under something `width` by `depth`, at `point` inside `parent`.
  func shadow(width: Float, depth: Float, at point: SIMD3<Float>, in parent: Entity? = nil) {
    guard let shadow = GenzGlow.shadow(width: width, depth: depth) else { return }
    shadow.position = point
    (parent ?? root).addChild(shadow)
    shadows.append(shadow)
    shade(shadow)
  }

  func setReduceMotion(_ reduced: Bool) { reduceMotion = reduced }

  /// Lights the scene for `look`, or with its own light when that is off.
  func apply(_ look: LightingLook) {
    self.look = look
    let lit = look.isLit
    for key in keys {
      let colour = tint(key.colour)
      key.light.components[PointLightComponent.self]?.color = colour.platformColour
      key.light.components[PointLightComponent.self]?.attenuationRadius =
        key.reach * (1 + 0.5 * (lit ? look.key.softness : 0))
    }
    setKeyBrightness()
    core.components[PointLightComponent.self]?.color = look.key.colour.genz.platformColour
    rim.components[SpotLightComponent.self]?.color = look.rim.colour.genz.platformColour
    setFillBrightness()
    sun.isEnabled = lit && look.sun.intensity > 0
    sun.components[DirectionalLightComponent.self]?.color = look.sun.colour.genz.platformColour
    sun.components[DirectionalLightComponent.self]?.intensity = look.sun.intensity
    for shadow in shadows { shade(shadow) }
    applyFill()
  }

  /// Brings the scene's lights down to `level` of their own, from 0 to 1.
  func setDimmer(_ level: Float) {
    let level = min(max(level, 0), 1)
    guard level != dimmer else { return }
    dimmer = level
    setKeyBrightness()
    setFillBrightness()
  }

  /// Steps a flickering key, as the candle preset asks.
  func step(_ delta: TimeInterval) {
    clock += delta
    if look.key.flicker > 0 { setKeyBrightness() }
  }

  /// How strongly the scene's halos show under this preset, where 1 is the scene's own.
  var haloScale: Double {
    look.isLit ? 0.55 + Double(look.halos) * 0.9 : 1
  }

  /// A lamp's halo colour under this preset, moved towards the key as its light is.
  func tint(_ colour: GenzColour) -> GenzColour {
    look.isLit ? GenzColour.mix(colour, look.key.colour.genz, by: look.key.warmth) : colour
  }

  /// The fairy lights' colour under this preset, or `nil` for the scene's own.
  var fairyColour: GenzColour? {
    look.isLit && look.fairy.shown ? look.fairy.colour.genz : nil
  }

  private var boost: Float {
    guard look.isLit else { return 1 }
    let flicker = look.key.flicker
    guard flicker > 0, !reduceMotion else { return look.key.boost }
    let wave = sin(clock * 9.1) * 0.5 + sin(clock * 23.7 + 1.3) * 0.3 + sin(clock * 3.3) * 0.2
    return look.key.boost * (1 - flicker * Float(0.5 + 0.5 * wave))
  }

  private func setKeyBrightness() {
    let boost = boost * dimmer
    for key in keys {
      key.light.components[PointLightComponent.self]?.intensity = key.intensity * boost
    }
  }

  private func setFillBrightness() {
    let lit = look.isLit
    core.components[PointLightComponent.self]?.intensity = lit ? look.core * dimmer : 0
    rim.components[SpotLightComponent.self]?.intensity = lit ? look.rim.intensity * dimmer : 0
  }

  private func shade(_ shadow: ModelEntity) {
    let darkness = look.isLit ? look.shadows : 0
    shadow.isEnabled = darkness > 0
    guard var material = shadow.model?.materials.first as? UnlitMaterial else { return }
    material.blending = .transparent(opacity: .init(floatLiteral: darkness))
    shadow.model?.materials = [material]
  }

  private func applyFill() {
    guard let ambient, var light = ambient.components[ImageBasedLightComponent.self] else {
      return
    }
    let fill = look.fill
    let lit = look.isLit
    let top = lit ? GenzColour.mix(ownAmbient.top, fill.top.genz, by: 0.75) : ownAmbient.top
    let bottom =
      lit ? GenzColour.mix(ownAmbient.bottom, fill.bottom.genz, by: 0.75) : ownAmbient.bottom
    if let environment = TabLook.ambient(top: top, bottom: bottom) {
      light.source = .single(environment)
    }
    light.intensityExponent = exponent + (lit ? fill.shift : 0)
    ambient.components.set(light)
  }
}
