import Foundation
import Pet
import PetScene
import RealityKit

/// Where the room's light switch stands, and the fade from one light to the next.
struct GenzLightSwitch {
  struct Fade {
    var from: LightingLook
    var lampFrom: Float
    var ledFrom: Float
    var start: Double
    var length: Double
  }

  var light = RoomLight.standard
  var fade: Fade?
  /// How bright the lamp is as the switch has it, from 0 (out) to 1, part way through a fade.
  var lampLevel: Float = 1
  /// How bright the LED strip's glow round the window is, the same way.
  var ledLevel: Float = 1
  /// The toggle on the plate, which flips up for light and down for dark, and the small warm
  /// dot that shows the lights are on.
  var toggle: ModelEntity?
  var indicator: ModelEntity?
  /// The plate itself, which pulses once the first time the room is shown.
  var plateEntity: Entity?
  /// The toggle's flip under way: where it started, and when.
  var flip: (from: Float, start: Double)?
  /// Where the toggle stands now, from -1 (down) to 1 (up).
  var toggleAt: Float = 1
  /// When the plate's one pulse started, while it plays, and whether it has been looked at for
  /// this room already.
  var pulseStart: Double?
  var pulseChecked = false
  /// The quarter of the fade the ambient light's colours were last remade at.
  var fillStep = 0

  /// How bright the lamp is with the switch at `light`.
  static func lampLevel(_ light: RoomLight) -> Float {
    switch light {
    case .on: 1
    case .cosy: 0.45
    case .off: 0
    }
  }

  /// How bright the LED strip's glow is with the switch at `light`: only the room's full light
  /// runs the strip.
  static func ledLevel(_ light: RoomLight) -> Float {
    switch light {
    case .on: 1
    case .cosy, .off: 0
    }
  }

  /// Where the toggle stands at `light`: up (1) while any light is on, down (-1) when it is all
  /// out, so it reads as a plain on/off switch at a glance.
  static func toggleStand(_ light: RoomLight) -> Float {
    switch light {
    case .on, .cosy: 1
    case .off: -1
    }
  }

  /// Whether the warm dot on the plate is lit at `light`.
  static func indicatorLit(_ light: RoomLight) -> Bool {
    switch light {
    case .on, .cosy: true
    case .off: false
    }
  }

  /// What VoiceOver says the switch is at: on or off, with the cosy light as a low on.
  static func spoken(_ light: RoomLight) -> String {
    switch light {
    case .on: "on"
    case .cosy: "on, low"
    case .off: "off"
    }
  }

  /// A flip takes about as long as a real toggle's snap.
  static let flipLength = 0.14

  /// Where the toggle is `elapsed` seconds into a flip from `from` to `to`. A press that leaves
  /// it where it stood (on to cosy) still dips it half way and back, so every press shows.
  static func toggle(from: Float, to: Float, elapsed: Double) -> Float {
    let t = Float(min(max(elapsed / flipLength, 0), 1))
    guard t < 1 else { return to }
    guard from != to else { return to - to * 0.5 * sin(t * .pi) }
    let eased = t * t * (3 - 2 * t)
    return from + (to - from) * eased
  }

  /// The plate's one pulse when the room is first shown: how long it takes, and how much the
  /// plate swells at its height, `elapsed` seconds in.
  static let pulseLength = 1.1
  static func pulseScale(_ elapsed: Double) -> Float {
    guard elapsed > 0, elapsed < pulseLength else { return 1 }
    return 1 + 0.16 * Float(sin(elapsed / pulseLength * .pi))
  }
  /// How long after the opening ends the plate pulses, so it is not lost in the fly-in.
  static let pulseDelay = 0.8
  /// The defaults key that remembers the pulse has played, once per install.
  static let introducedKey = "genz.lightSwitch.introduced"

  /// Whether the pulse is still to play on this install, marking it played if so.
  static func claimPulse(in defaults: UserDefaults) -> Bool {
    guard !defaults.bool(forKey: introducedKey) else { return false }
    defaults.set(true, forKey: introducedKey)
    return true
  }

  /// A fade takes about as long as an old bulb takes to warm up or die down.
  static let fadeLength = 0.55
  static let reducedFadeLength = 0.2

  /// How far into the fade `elapsed` seconds are, eased out so the change lands at once and
  /// settles softly.
  static func progress(_ elapsed: Double, length: Double) -> Float {
    guard length > 0 else { return 1 }
    let t = min(max(elapsed / length, 0), 1)
    return Float(1 - pow(1 - t, 3))
  }

  /// The plate on the back wall in the strip left of the window: its middle in room units. The
  /// rest of the walls fall outside the view from home on a phone, and it hangs high enough to
  /// show over the tallest piece any set stands in that corner, the bookshelf.
  static let plate = GenzRoomPoint(0.27, 0, 4.02)
  /// The plate's size along the wall and up it, and how far it stands out. Narrow enough to keep
  /// clear of the LED strip round the window.
  static let plateSize = SIMD2<Float>(0.42, 0.68)
  static let plateDepth: Float = 0.06
  /// How far the shadow's nearest layer stands off the wall: in front of a style's wall skin (`GenzRoomStyler.lift`), and
  /// each layer far enough from the next that none flickers against another.
  static let shadowLift: Float = 0.016
  /// How much bigger than the plate a finger may land and still press it.
  static let reach = SIMD2<Float>(1.0, 1.4)
}

@MainActor
extension GenzRoom {
  /// Hangs the switch plate on the back wall, left of the window: a cream plate with a soft
  /// shadow on the wall, a dark slot with a toggle up or down in it, and a warm dot under it that
  /// glows while the lights are on.
  func buildSwitchPlate() {
    let plate = Entity()
    plate.name = Self.switchName
    let at = GenzLightSwitch.plate
    plate.position = at.scene
    let size = GenzLightSwitch.plateSize
    let depth = GenzLightSwitch.plateDepth
    // Out of the back wall is the scene's +z. The shadow is three faint layers, each a little
    // wider, so its edge falls off softly; it sits a touch low, as if lit from above.
    for (index, grow) in [Float(0.03), 0.07, 0.12].enumerated() {
      plate.addChild(
        kit.part(
          kit.plane(width: size.x + grow, height: size.y + grow),
          kit.glow(GenzColour(0x1A120A), opacity: 0.16),
          at: [0, -0.04, GenzLightSwitch.shadowLift + Float(index) * 0.006]))
    }
    plate.addChild(
      kit.part(
        LowPoly.roundedBox([size.x, size.y, depth], radius: 0.03), kit.matte(GenzColour(0xF1E7D2)),
        at: [0, 0, depth / 2]))
    let slot = SIMD2(size.x * 0.4, size.y * 0.5)
    plate.addChild(
      kit.part(
        LowPoly.roundedBox([slot.x, slot.y, 0.012], radius: 0.006), kit.matte(GenzColour(0x5C4A36)),
        at: [0, size.y * 0.04, depth + 0.004]))
    let toggle = kit.part(
      LowPoly.roundedBox([slot.x * 0.78, slot.y * 0.5, 0.07], radius: 0.02),
      kit.matte(GenzColour(0xFFFAF0)))
    plate.addChild(toggle)
    let indicator = kit.part(
      LowPoly.roundedBox([0.06, 0.06, 0.02], radius: 0.01),
      kit.glow(indicatorColour(lightSwitch.light)), at: [0, -size.y * 0.36, depth + 0.008])
    plate.addChild(indicator)
    let reach = GenzLightSwitch.reach
    SceneParts.makeTappable(plate, size: [reach.x, reach.y, 0.3], center: [0, 0, 0.15])
    room.addChild(plate)
    lightSwitch.plateEntity = plate
    lightSwitch.toggle = toggle
    lightSwitch.indicator = indicator
    lightSwitch.flip = nil
    placeToggle(GenzLightSwitch.toggleStand(lightSwitch.light))
  }

  /// Stands the toggle at `stand`, from -1 (down) to 1 (up): it slides to that end of the slot and
  /// leans out at it, as a real toggle's lever does.
  func placeToggle(_ stand: Float) {
    lightSwitch.toggleAt = stand
    guard let toggle = lightSwitch.toggle else { return }
    let size = GenzLightSwitch.plateSize
    let depth = GenzLightSwitch.plateDepth
    toggle.position = [0, size.y * 0.04 + stand * size.y * 0.11, depth + 0.04]
    toggle.orientation = simd_quatf(angle: -stand * 0.45, axis: [1, 0, 0])
  }

  /// Moves the toggle's flip and the plate's first pulse on by a frame, and starts the pulse the
  /// first time the room has opened.
  func stepSwitchPlate() {
    if let flip = lightSwitch.flip {
      let target = GenzLightSwitch.toggleStand(lightSwitch.light)
      let elapsed = clock - flip.start
      placeToggle(GenzLightSwitch.toggle(from: flip.from, to: target, elapsed: elapsed))
      if elapsed >= GenzLightSwitch.flipLength { lightSwitch.flip = nil }
    }
    if !lightSwitch.pulseChecked, opening == nil, let openedClock,
      clock - openedClock > GenzOpening.length + GenzLightSwitch.pulseDelay
    {
      lightSwitch.pulseChecked = true
      if GenzLightSwitch.claimPulse(in: spots.defaults), !reduceMotion {
        lightSwitch.pulseStart = clock
      }
    }
    if let start = lightSwitch.pulseStart {
      let scale = GenzLightSwitch.pulseScale(clock - start)
      lightSwitch.plateEntity?.scale = [scale, scale, 1]
      if clock - start >= GenzLightSwitch.pulseLength { lightSwitch.pulseStart = nil }
    }
  }

  /// A press on the plate: the switch moves on, the room starts fading to it at once, and the
  /// host is told so it can keep it and tell the partner.
  func pressSwitch() -> PetSceneEvent {
    let next = lightSwitch.light.next
    setRoomLight(next, animated: true)
    screen.switchPresses += 1
    return .lightSwitched(next)
  }

  /// Sets the switch to `light`, from a press here or the partner's. Off screen, or before the
  /// room is built, the room goes straight to it.
  func setRoomLight(_ light: RoomLight, animated: Bool = true) {
    guard light != lightSwitch.light else { return }
    let before = lightSwitch.light
    lightSwitch.light = light
    screen.roomLight = light
    lightSwitch.indicator?.model?.materials = [kit.glow(indicatorColour(light))]
    if isBuilt, isOnScreen, !reduceMotion {
      lightSwitch.flip = (lightSwitch.toggleAt, clock)
    } else {
      lightSwitch.flip = nil
      placeToggle(GenzLightSwitch.toggleStand(light))
    }
    relight(animated: animated && isBuilt && isOnScreen)
    guard isBuilt else { return }
    if light == .off {
      behaviour.lightsOut(at: clock)
    } else if before == .off {
      behaviour.lightsOn(at: clock)
    }
  }

  /// Lights the room for the preset as the switch has it, fading from what it shows now when
  /// `animated`.
  func relight(animated: Bool) {
    if animated {
      lightSwitch.fade = GenzLightSwitch.Fade(
        from: look, lampFrom: lightSwitch.lampLevel, ledFrom: lightSwitch.ledLevel, start: clock,
        length: reduceMotion ? GenzLightSwitch.reducedFadeLength : GenzLightSwitch.fadeLength)
      lightSwitch.fillStep = 0
      stepSwitch()
      return
    }
    lightSwitch.fade = nil
    lightSwitch.lampLevel = GenzLightSwitch.lampLevel(lightSwitch.light)
    lightSwitch.ledLevel = GenzLightSwitch.ledLevel(lightSwitch.light)
    screen.ledLevel = Double(lightSwitch.ledLevel)
    let target = LightingLook.switched(preset, to: lightSwitch.light).tinted(style.fairy)
    guard target != look else { return }
    setLook(target)
    applyLook()
  }

  /// Moves a fade on by a frame. The lights and the flat layers follow every frame; the ambient
  /// light's colours are remade at each quarter, as remaking them costs more than a frame's share.
  func stepSwitch() {
    guard let fade = lightSwitch.fade else { return }
    let target = LightingLook.switched(preset, to: lightSwitch.light).tinted(style.fairy)
    let progress = GenzLightSwitch.progress(clock - fade.start, length: fade.length)
    let lampTarget = GenzLightSwitch.lampLevel(lightSwitch.light)
    lightSwitch.lampLevel = fade.lampFrom + (lampTarget - fade.lampFrom) * progress
    let ledTarget = GenzLightSwitch.ledLevel(lightSwitch.light)
    lightSwitch.ledLevel = fade.ledFrom + (ledTarget - fade.ledFrom) * progress
    screen.ledLevel = Double(lightSwitch.ledLevel)
    setLook(
      LightingLook.mix(
        fade.from, target, by: progress, ownLED: layout.ledColour.rgb, ownOutside: outsideColour.rgb
      ))
    let step = Int(progress * 4)
    let remakesFill = step != lightSwitch.fillStep || progress >= 1
    lightSwitch.fillStep = step
    applyLook(fill: remakesFill)
    if progress >= 1 { lightSwitch.fade = nil }
  }

  /// The dot on the plate: a warm glow while the lights are on, lower for the cosy light, and a
  /// dull ember when they are out.
  private func indicatorColour(_ light: RoomLight) -> GenzColour {
    switch light {
    case .on: GenzColour(0xFFB347)
    case .cosy: GenzColour(0xE0913A)
    case .off: GenzColour(0x4A3A2A)
    }
  }
}
