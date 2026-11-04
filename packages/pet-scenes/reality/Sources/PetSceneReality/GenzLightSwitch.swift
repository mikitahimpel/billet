import Pet
import PetScene
import RealityKit

/// Where the room's light switch stands, and the fade from one light to the next.
struct GenzLightSwitch {
  struct Fade {
    var from: LightingLook
    var lampFrom: Float
    var start: Double
    var length: Double
  }

  var light = RoomLight.standard
  var fade: Fade?
  /// How bright the lamp is as the switch has it, from 0 (out) to 1, part way through a fade.
  var lampLevel: Float = 1
  /// The rocker on the plate, which tips with the switch, and the small light that finds the
  /// switch in the dark.
  var rocker: ModelEntity?
  var finder: ModelEntity?
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

  /// How far the rocker tips up (positive) or down at `light`, in room units.
  static func rockerLift(_ light: RoomLight) -> Float {
    switch light {
    case .on: 0.06
    case .cosy: 0
    case .off: -0.06
    }
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

  /// The plate on the back wall in the strip left of the window, at shoulder height: its middle
  /// in room units. The rest of the walls fall outside the view from home on a phone.
  static let plate = GenzRoomPoint(0.27, 0, 2.55)
  /// The plate's size along the wall and up it, and how far it stands out. Narrow enough to keep
  /// clear of the LED strip round the window.
  static let plateSize = SIMD2<Float>(0.34, 0.56)
  static let plateDepth: Float = 0.05
  /// How much bigger than the plate a finger may land and still press it.
  static let reach = SIMD2<Float>(0.9, 1.3)
}

@MainActor
extension GenzRoom {
  /// Hangs the switch plate on the back wall, left of the window. It is three small boxes: the plate, the
  /// rocker, and a pin of light that glows when the room is dark so the switch can be found.
  func buildSwitchPlate() {
    let plate = Entity()
    plate.name = Self.switchName
    let at = GenzLightSwitch.plate
    plate.position = at.scene
    let size = GenzLightSwitch.plateSize
    let depth = GenzLightSwitch.plateDepth
    let face = kit.matte(GenzColour(0xEFE6D4))
    // Out of the back wall is the scene's +z.
    plate.addChild(kit.part(kit.box([size.x, size.y, depth]), face, at: [0, 0, depth / 2]))
    let rocker = kit.part(
      kit.box([size.x * 0.4, size.y * 0.38, depth]), kit.matte(GenzColour(0xF8F2E6)),
      at: [0, GenzLightSwitch.rockerLift(lightSwitch.light), depth * 1.5])
    plate.addChild(rocker)
    let finder = kit.part(
      kit.box([0.035, 0.035, depth * 0.6]), kit.glow(finderColour(lightSwitch.light)),
      at: [0, size.y * 0.36, depth * 1.3])
    plate.addChild(finder)
    let reach = GenzLightSwitch.reach
    SceneParts.makeTappable(plate, size: [reach.x, reach.y, 0.3], center: [0, 0, 0.15])
    room.addChild(plate)
    lightSwitch.rocker = rocker
    lightSwitch.finder = finder
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
    lightSwitch.rocker?.position.y = GenzLightSwitch.rockerLift(light)
    lightSwitch.finder?.model?.materials = [kit.glow(finderColour(light))]
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
        from: look, lampFrom: lightSwitch.lampLevel, start: clock,
        length: reduceMotion ? GenzLightSwitch.reducedFadeLength : GenzLightSwitch.fadeLength)
      lightSwitch.fillStep = 0
      stepSwitch()
      return
    }
    lightSwitch.fade = nil
    lightSwitch.lampLevel = GenzLightSwitch.lampLevel(lightSwitch.light)
    let target = LightingLook.switched(preset, to: lightSwitch.light)
    guard target != look else { return }
    setLook(target)
    applyLook()
  }

  /// Moves a fade on by a frame. The lights and the flat layers follow every frame; the ambient
  /// light's colours are remade at each quarter, as remaking them costs more than a frame's share.
  func stepSwitch() {
    guard let fade = lightSwitch.fade else { return }
    let target = LightingLook.switched(preset, to: lightSwitch.light)
    let progress = GenzLightSwitch.progress(clock - fade.start, length: fade.length)
    let lampTarget = GenzLightSwitch.lampLevel(lightSwitch.light)
    lightSwitch.lampLevel = fade.lampFrom + (lampTarget - fade.lampFrom) * progress
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

  /// The pin of light on the plate: bright in the dark, faint when the room is lit.
  private func finderColour(_ light: RoomLight) -> GenzColour {
    switch light {
    case .on: GenzColour(0x6E5A3C)
    case .cosy: GenzColour(0xB08850)
    case .off: GenzColour(0xFFC873)
    }
  }
}
