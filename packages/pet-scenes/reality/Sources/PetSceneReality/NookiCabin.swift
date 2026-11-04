import Foundation
import Pet
import RealityKit
import SwiftUI

/// The Nooki project's cabin (nexishq/nooki-ios, `DioramaScene`): a snowed-in corner of a room seen
/// from above, built from rounded boxes, spheres and cylinders in warm clay colours. Its numbers
/// are the Nooki project's, in its metres, with the floor's top at 0 and the walls' inner faces at
/// -0.5, scaled here into room units.
enum NookiCabin {
  /// Room units to one of the Nooki project's metres.
  static let scale: Float = 6
  /// The height of the Nooki project's planks, taken off everything so their tops are the floor.
  static let plankTop: Float = 0.014
  static let wallHeight: Float = 0.8

  /// A point in the Nooki project's metres as a point in the room.
  static func room(_ x: Float, _ y: Float, _ z: Float) -> GenzRoomPoint {
    GenzRoomPoint((x + 0.5) * scale, (z + 0.5) * scale, (y - plankTop) * scale)
  }

  /// A point in the Nooki project's metres in the scene.
  static func scene(_ point: SIMD3<Float>) -> SIMD3<Float> {
    room(point.x, point.y, point.z).scene
  }

  enum Tone {
    static let wood: UInt32 = 0xB46C3C
    static let woodDark: UInt32 = 0x8C4F2B
    static let woodLight: UInt32 = 0xCF8E58
    static let wall: UInt32 = 0xF6E4C8
    static let snow: UInt32 = 0xFFFBF5
    static let blanket: UInt32 = 0xE98A5B
    static let plush: UInt32 = 0xFBF1E3
    static let plushShade: UInt32 = 0xEADBC6
    static let rug: UInt32 = 0xDDB98A
    static let rugEdge: UInt32 = 0xC39A69
    static let leaf: UInt32 = 0x93A86A
    static let leafDark: UInt32 = 0x6F8A4E
    static let pot: UInt32 = 0xC7744A
    static let ink: UInt32 = 0x5B3A28
    static let windowGlow: UInt32 = 0xFFE0A0
    static let bulb: UInt32 = 0xFFD27A
    static let flame: UInt32 = 0xFFB347
  }

  /// The garland of polaroids on the back wall, left of the shelf: its two ends and how far it
  /// sags in the middle.
  static let garland = (x0: Float(-0.42), x1: Float(0), y: Float(0.64), sag: Float(0.035))

  static func garlandPoint(_ t: Float) -> SIMD3<Float> {
    [
      garland.x0 + (garland.x1 - garland.x0) * t, garland.y - garland.sag * sin(t * .pi),
      -0.492,
    ]
  }

  /// The note, pinned to the middle of the garland in a polaroid of its own.
  static let note = (width: Float(0.15), height: Float(0.16), drop: Float(0.012))

  static var noteCentre: SIMD3<Float> {
    garlandPoint(0.5) + [0, -note.drop - note.height / 2 - 0.012, 0.009]
  }

  static let window: SIMD3<Float> = [-0.49, 0.47, 0.02]
  static let windowRadius: Float = 0.172
}

extension GenzLayout {
  /// The Nooki cabin, with the cat in its plush bed on the rug.
  static let nookiCabin: GenzLayout = {
    let room = NookiCabin.room
    let noteAt = NookiCabin.noteCentre
    let window = NookiCabin.window
    let radius = NookiCabin.windowRadius
    let scale = NookiCabin.scale
    func place(
      _ kind: GenzPiece.Kind, _ x: Float, _ z: Float, height y: Float = NookiCabin.plankTop
    )
      -> Placement
    {
      Placement(piece: GenzPiece(kind), centre: room(x, y, z))
    }
    return GenzLayout(
      // The Nooki project's camera looks down along (1, 0.82, 1) with a narrow lens, from 5.9 m.
      camera: GenzCamera.Home(
        target: room(-0.02, 0.2, 0.02).scene, yaw: .pi / 4, pitch: 0.525, distance: 35,
        fieldOfView: 22, yawLimits: 0.035...1.535, pitchLimits: 0.35...0.85,
        zoomLimits: 0.5...1.25),
      pieces: [
        place(.cabinRug, 0, 0.04),
        place(.cabinBed, 0.06, -0.04),
        place(.cabinCatTree, 0.36, -0.36),
        place(.cabinNightstand, -0.39, 0.33, height: NookiCabin.plankTop),
        place(.cabinPlant, -0.4, -0.4),
        place(.cabinBasket, 0.37, 0.36),
        place(.cabinStoolLamp, -0.1, -0.42),
        place(.cabinBooks, 0.2, 0.4),
      ],
      // In the bed, turned to look out between the camera and the window.
      cat: (room(0.06, NookiCabin.plankTop, -0.03), 3.9, 1.25),
      note: Panel(
        centre: room(noteAt.x, noteAt.y, noteAt.z),
        width: NookiCabin.note.width * scale, height: NookiCabin.note.height * scale),
      paper: GenzColour(0xFFFBF3),
      led: [],
      ledColour: GenzColour(NookiCabin.Tone.bulb),
      window: [
        room(-0.5, window.y + radius, window.z - radius),
        room(-0.5, window.y + radius, window.z + radius),
        room(-0.5, window.y - radius, window.z + radius),
        room(-0.5, window.y - radius, window.z - radius),
      ],
      lamp: (room(-0.15, 0.31, -0.34), room(-0.1, 0, -0.2)),
      lampColour: GenzColour(0xFFC27A),
      shell: NookiCabin.shell,
      floor: [6, 6],
      // The cat lives on the floor, among the furniture, rather than up on a piece.
      catTop: ([0.35, 0.35], [5.65, 5.65]),
      room: .nookiCabin,
      // The Nooki project's warm two-tone sky, cream over toffee.
      ambient: GenzAmbient(top: GenzColour(0xFFE7C4), bottom: GenzColour(0xB97A45), exponent: 0.4),
      // The cabin hangs its own fairy lights, lit always.
      ownFairyHooks: [],
      sunFrom: room(1.4, 2.2, 0.9),
      switchPlate: room(0.06, 0.42, -0.5),
      ownLights: NookiCabin.lights)
  }()
}

/// A light of the room's own, beyond the lamp: placed, and lit to `intensity` as the room opens.
struct GenzOwnLight {
  let entity: Entity
  let intensity: Float
  /// How much it flickers, as a share of its intensity: a candle's flame.
  var flicker: Float = 0
}

@MainActor
extension NookiCabin {
  /// The sun with its shadows, the window's warm spill and the candle on the nightstand. The
  /// lamp on the stool is the room's lamp. Point lights reach as far in room units as the
  /// Nooki project's in metres, and are as bright where they land.
  static func lights() -> [GenzOwnLight] {
    let area = scale * scale
    let sun = Entity()
    sun.components.set(
      DirectionalLightComponent(color: GenzColour(0xFFE2BC).platformColour, intensity: 0))
    sun.components.set(
      DirectionalLightComponent.Shadow(maximumDistance: 4 * scale, depthBias: 2))
    sun.look(at: scene([0, 0, 0]), from: scene([1.4, 2.2, 0.9]), relativeTo: nil)
    let window = Entity()
    window.position = scene([-0.3, 0.47, 0.02])
    window.components.set(
      PointLightComponent(
        color: GenzColour(0xFFB866).platformColour, intensity: 0,
        attenuationRadius: 1.1 * scale))
    let candle = Entity()
    candle.position = scene([-0.37, 0.33, 0.38])
    var flame = PointLightComponent(
      color: GenzColour(0xFFAA55).platformColour, intensity: 0, attenuationRadius: 0.6 * scale)
    flame.attenuationFalloffExponent = 2
    candle.components.set(flame)
    return [
      GenzOwnLight(entity: sun, intensity: 900),
      GenzOwnLight(entity: window, intensity: 1_800 * area * 0.6),
      GenzOwnLight(entity: candle, intensity: 450 * area * 0.6, flicker: 0.15),
    ]
  }

  /// The floor, the two walls with their posts, beams and snow, the round window, the shelf, the
  /// garland and the fairy lights.
  static func shell(_ kit: GenzKit) -> [Entity] {
    var clay = CabinClay(kit: kit, origin: scene(.zero), scale: scale)
    buildFloor(&clay)
    buildWalls(&clay)
    buildWindow(&clay)
    buildShelf(&clay)
    buildGarland(&clay)
    buildFairyLights(&clay)
    return clay.parts + clay.joinedGlows()
  }

  private static func buildFloor(_ c: inout CabinClay) {
    c.box(1.14, 0.1, 1.14, r: 0.03, Tone.woodDark, at: [-0.01, -0.05, -0.01])
    for i in 0..<7 {
      let z = -0.45 + Float(i) * 0.15
      let tone = i.isMultiple(of: 2) ? Tone.wood : Tone.woodLight
      c.box(1.04, 0.014, 0.146, r: 0.005, tone, at: [0, 0.007, z])
    }
  }

  private static func buildWalls(_ c: inout CabinClay) {
    let h = wallHeight
    c.box(0.05, h, 1.06, r: 0.01, Tone.wall, at: [-0.525, h / 2, -0.03])
    c.box(1.06, h, 0.05, r: 0.01, Tone.wall, at: [-0.03, h / 2, -0.525])
    c.box(0.014, 0.05, 1.0, r: 0.004, Tone.wood, at: [-0.493, 0.025, 0])
    c.box(1.0, 0.05, 0.014, r: 0.004, Tone.wood, at: [0, 0.025, -0.493])
    for (x, z) in [(-0.535, 0.52), (-0.535, -0.535), (0.52, -0.535)] as [(Float, Float)] {
      c.box(0.075, h + 0.06, 0.075, r: 0.012, Tone.wood, at: [x, (h + 0.06) / 2, z])
    }
    c.box(0.085, 0.065, 1.13, r: 0.015, Tone.wood, at: [-0.535, h + 0.02, -0.01])
    c.box(1.13, 0.065, 0.085, r: 0.015, Tone.wood, at: [-0.01, h + 0.02, -0.535])
    // Snow on the beams.
    c.box(0.12, 0.05, 0.42, r: 0.024, Tone.snow, at: [-0.535, h + 0.07, 0.22])
    c.box(0.11, 0.04, 0.3, r: 0.019, Tone.snow, at: [-0.535, h + 0.065, -0.28])
    c.sphere(0.04, Tone.snow, at: [-0.535, h + 0.075, 0], scale: [1.2, 0.8, 1.4])
    c.box(0.44, 0.05, 0.12, r: 0.024, Tone.snow, at: [0.24, h + 0.07, -0.535])
    c.box(0.26, 0.04, 0.11, r: 0.019, Tone.snow, at: [-0.3, h + 0.065, -0.535])
    c.sphere(0.045, Tone.snow, at: [-0.535, h + 0.08, -0.535], scale: [1.3, 0.9, 1.3])
  }

  /// A round window in the side wall, glowing warm, with muntins and a sill.
  private static func buildWindow(_ c: inout CabinClay) {
    let centre = window
    let facingX = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
    c.cylinder(0.03, 0.215, Tone.wood, at: centre, turn: facingX)
    c.cylinder(
      0.032, windowRadius, Tone.windowGlow, at: centre + [0.003, 0, 0], turn: facingX, glows: true)
    for dz: Float in [-0.06, 0.06] {
      c.box(0.014, 0.34, 0.016, r: 0.004, Tone.wood, at: [-0.466, centre.y, centre.z + dz])
    }
    for dy: Float in [-0.06, 0.06] {
      c.box(0.014, 0.016, 0.34, r: 0.004, Tone.wood, at: [-0.466, centre.y + dy, centre.z])
    }
    c.box(0.09, 0.022, 0.4, r: 0.008, Tone.woodLight, at: [-0.465, 0.262, 0.02])
    c.cylinder(0.05, 0.022, Tone.pot, at: [-0.46, 0.298, -0.1])
    c.sphere(0.03, Tone.leaf, at: [-0.46, 0.34, -0.1], scale: [1, 0.8, 1])
    c.cylinder(0.045, 0.018, 0xF2E6D2, at: [-0.46, 0.295, 0.14])
  }

  private static func buildShelf(_ c: inout CabinClay) {
    let s: SIMD3<Float> = [0.27, 0.6, -0.44]
    c.box(0.3, 0.25, 0.014, r: 0.004, Tone.woodDark, at: [s.x, s.y, -0.494])
    for dy: Float in [-0.125, 0, 0.125] {
      c.box(0.33, 0.02, 0.12, r: 0.006, Tone.wood, at: [s.x, s.y + dy, s.z])
    }
    for dx: Float in [-0.155, 0.155] {
      c.box(0.02, 0.27, 0.12, r: 0.006, Tone.wood, at: [s.x + dx, s.y, s.z])
    }
    let books: [UInt32] = [0xC0563A, 0x7C9A7E, 0xE3B45C, 0x9A7BB8, 0xDA8E6B, 0x6F8FB0]
    var x = s.x - 0.13
    for (i, tone) in books.enumerated() {
      let h: Float = 0.075 + Float(i % 3) * 0.012
      c.box(0.024, h, 0.085, r: 0.004, tone, at: [x, s.y - 0.115 + h / 2, s.z])
      x += 0.028
    }
    c.box(0.12, 0.022, 0.085, r: 0.004, 0xE3B45C, at: [s.x - 0.06, s.y + 0.021, s.z])
    c.box(0.11, 0.022, 0.08, r: 0.004, 0xC0563A, at: [s.x - 0.06, s.y + 0.043, s.z])
    c.cylinder(0.07, 0.025, 0xFFE7B8, at: [s.x + 0.08, s.y + 0.045, s.z], glows: true)
  }

  /// Twine along the back wall with polaroids pegged to it. The middle two slots make way for
  /// the note, which hangs in a bigger frame of its own.
  private static func buildGarland(_ c: inout CabinClay) {
    let steps = 12
    for i in 0..<steps {
      let a = garlandPoint(Float(i) / Float(steps))
      let b = garlandPoint(Float(i + 1) / Float(steps))
      let d = b - a
      c.box(
        simd_length(d) + 0.002, 0.003, 0.003, r: 0, 0xB89A78, at: (a + b) / 2,
        turn: simd_quatf(angle: atan2(d.y, d.x), axis: [0, 0, 1]))
    }
    let tilts: [Float] = [0.07, -0.05, 0.04, -0.08, 0.06, -0.03]
    let prints: [UInt32] = [0xE9A07A, 0x8DB0C9, 0, 0, 0xA9C48E, 0xE3B45C]
    for slot in [0, 1, 4, 5] {
      let top = garlandPoint((Float(slot) + 0.5) / 6)
      let turn = simd_quatf(angle: tilts[slot], axis: [0, 0, 1])
      let card = top + [0, -0.004, 0]
      c.box(
        0.066, 0.08, 0.004, r: 0.002, 0xFFFBF3, at: card + turn.act([0, -0.04, 0.002]), turn: turn)
      c.box(0.012, 0.018, 0.008, r: 0.002, Tone.woodLight, at: card + [0, 0, 0.004], turn: turn)
      c.box(
        0.056, 0.056, 0.001, r: 0, prints[slot], at: card + turn.act([0, -0.033, 0.0045]),
        turn: turn)
    }
    // The note's frame and peg; the room hangs the note itself in front.
    let note = NookiCabin.note
    let middle = garlandPoint(0.5)
    c.box(
      note.width + 0.016, note.height + 0.034, 0.004, r: 0.002, 0xFFFBF3,
      at: noteCentre + [0, -0.008, -0.006])
    c.box(0.016, 0.024, 0.01, r: 0.002, Tone.woodLight, at: middle + [0, -0.008, 0.006])
  }

  private static func buildFairyLights(_ c: inout CabinClay) {
    let top = wallHeight - 0.05
    let count = 13
    for i in 0..<count {
      let t = Float(i) / Float(count - 1)
      let sag = 0.05 * abs(sin(t * .pi * 2))
      c.sphere(0.011, Tone.bulb, at: [-0.47 + t * 0.94, top - sag, -0.47], glows: true)
      c.sphere(0.011, Tone.bulb, at: [-0.47, top - sag, -0.47 + t * 0.94], glows: true)
    }
  }
}

/// Builds the Nooki project's shapes, given in its metres, as parts in room units. Matte parts
/// share the kit's materials, so the room joins them into one model per colour; glowing parts of
/// one colour are joined here.
@MainActor
struct CabinClay {
  let kit: GenzKit
  /// Where the Nooki project's origin is, in the frame the parts are placed in.
  let origin: SIMD3<Float>
  let scale: Float
  private(set) var parts: [Entity] = []
  private var glowing: [UInt32: [ModelEntity]] = [:]
  private var glowOrder: [UInt32] = []

  init(kit: GenzKit, origin: SIMD3<Float>, scale: Float) {
    self.kit = kit
    self.origin = origin
    self.scale = scale
  }

  mutating func box(
    _ w: Float, _ h: Float, _ d: Float, r: Float = 0.01, _ hex: UInt32, at p: SIMD3<Float>,
    turn: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]), glows: Bool = false
  ) {
    let size = SIMD3(w, h, d) * scale
    let radius = max(min(r, min(w, min(h, d)) / 2 - 0.0005), 0) * scale
    let mesh =
      radius > 0
      ? LowPoly.roundedBox(size, radius: radius, steps: 2) : kit.box(size)
    add(mesh, hex, at: p, scale: .one, turn: turn, glows: glows)
  }

  mutating func sphere(
    _ radius: Float, _ hex: UInt32, at p: SIMD3<Float>, scale stretch: SIMD3<Float> = .one,
    turn: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]), glows: Bool = false
  ) {
    add(
      LowPoly.sphere(radius: radius * scale, segments: 12), hex, at: p, scale: stretch,
      turn: turn, glows: glows)
  }

  mutating func cylinder(
    _ height: Float, _ radius: Float, _ hex: UInt32, at p: SIMD3<Float>,
    scale stretch: SIMD3<Float> = .one,
    turn: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]), glows: Bool = false
  ) {
    add(
      LowPoly.cylinder(height: height * scale, radius: radius * scale, segments: 20), hex, at: p,
      scale: stretch, turn: turn, glows: glows)
  }

  private mutating func add(
    _ mesh: MeshResource, _ hex: UInt32, at p: SIMD3<Float>, scale stretch: SIMD3<Float>,
    turn: simd_quatf, glows: Bool
  ) {
    let colour = GenzColour(hex)
    let model = kit.part(
      mesh, glows ? kit.glow(colour) : kit.matte(colour), at: origin + p * scale, turn: turn)
    model.scale = stretch
    if glows {
      if glowing[hex] == nil { glowOrder.append(hex) }
      glowing[hex, default: []].append(model)
    } else {
      parts.append(model)
    }
  }

  /// The glowing parts, one model per colour.
  func joinedGlows() -> [Entity] {
    glowOrder.compactMap { hex -> Entity? in
      guard let models = glowing[hex] else { return nil }
      guard models.count > 1 else { return models.first }
      let holder = Entity()
      for model in models { holder.addChild(model) }
      guard let mesh = GenzKit.joined(models, in: holder) else { return holder }
      return ModelEntity(mesh: mesh, materials: [kit.glow(GenzColour(hex))])
    }
  }
}

/// Behind the cabin: the Nooki project's dark amber vignette with drifting bokeh, standing in for
/// a camera's shallow focus. The bokeh drifts a few times a second, and holds still while the
/// room is off screen or motion is reduced.
struct NookiCabinBackdrop: View {
  let isPaused: Bool

  var body: some View {
    ZStack {
      RadialGradient(
        colors: [
          Color(red: 0.957, green: 0.749, blue: 0.494),
          Color(red: 0.702, green: 0.431, blue: 0.227),
          Color(red: 0.290, green: 0.173, blue: 0.106),
          Color(red: 0.141, green: 0.082, blue: 0.051),
        ],
        center: UnitPoint(x: 0.5, y: 0.48), startRadius: 10, endRadius: 520)
      TimelineView(.animation(minimumInterval: 1.0 / 6, paused: isPaused)) { context in
        Canvas { ctx, size in
          let t = context.date.timeIntervalSinceReferenceDate
          for i in 0..<14 {
            let seed = Double(i) * 12.9898
            let x = (sin(seed) * 0.5 + 0.5) * size.width + sin(t * 0.15 + seed) * 18
            let y = (cos(seed * 1.7) * 0.5 + 0.5) * size.height + cos(t * 0.12 + seed) * 24
            let r = 6 + (sin(seed * 3.1) * 0.5 + 0.5) * 16
            let alpha = 0.18 + 0.14 * sin(t * 0.6 + seed)
            let bokeh = Color(red: 1, green: 0.843, blue: 0.604)
            // A soft-edged disc, cheaper than blurring the whole layer.
            ctx.fill(
              Path(
                ellipseIn: CGRect(x: x - r * 1.4, y: y - r * 1.4, width: r * 2.8, height: r * 2.8)),
              with: .radialGradient(
                Gradient(colors: [bokeh.opacity(alpha), bokeh.opacity(alpha * 0.6), .clear]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 1.4))
          }
        }
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
