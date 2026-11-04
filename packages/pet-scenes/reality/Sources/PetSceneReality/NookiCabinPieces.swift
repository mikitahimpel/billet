import Foundation
import RealityKit

/// The Nooki cabin's furniture, from the Nooki project's `DioramaScene` in its metres. Each is built
/// round the point the Nooki project places it at, which here is the middle of its footprint.
@MainActor
extension GenzKit {
  /// Shapes for `piece`, placed round the middle of its footprint.
  private func cabinClay(_ piece: GenzPiece) -> CabinClay {
    let size = piece.kind.size
    // The Nooki project's pieces stand on its planks; the nightstand alone stands on the floor
    // under them, so it sits a plank lower.
    let lift: Float = piece.kind == .cabinNightstand ? -NookiCabin.plankTop : 0
    let scale = NookiCabin.scale * (piece.kind == .cabinBed ? Self.bedScale : 1)
    return CabinClay(
      kit: self, origin: [size.x / 2, lift * NookiCabin.scale, size.y / 2], scale: scale)
  }

  private func slotHex(_ piece: GenzPiece, _ index: Int) -> UInt32 { Self.hex(piece.slot(index)) }

  func cabinRug(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    // Thinner than the Nooki project's, so toys lying on it are on top of it.
    c.cylinder(0.002, 0.33, slotHex(piece, 0), at: [0, 0.001, 0])
    c.cylinder(0.002, 0.31, slotHex(piece, 1), at: [0, 0.002, 0])
    return c.parts
  }

  /// A round donut bed: a soft base, a lumpy ring of plush and tufts on the rim. It is lower than
  /// the Nooki project's, so a cat lying in it on the floor shows over the rim.
  func cabinBed(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    let (plush, shade) = (slotHex(piece, 0), slotHex(piece, 1))
    c.cylinder(0.03, 0.19, shade, at: [0, 0.015, 0])
    c.cylinder(0.012, 0.15, plush, at: [0, 0.028, 0])
    let lumps = 24
    for i in 0..<lumps {
      let a = Float(i) / Float(lumps) * 2 * .pi
      let wobble = 1 + 0.06 * sin(Float(i) * 2.7)
      c.sphere(
        0.05 * wobble, i.isMultiple(of: 2) ? plush : shade,
        at: [cos(a) * 0.17, 0.048, sin(a) * 0.17], scale: [1, 0.82, 1])
    }
    for i in 0..<40 {
      let a = Float(i) / 40 * 2 * .pi + 0.08
      let r: Float = 0.17 + 0.02 * sin(Float(i) * 5.1)
      c.sphere(0.02, plush, at: [cos(a) * r, 0.084 + 0.008 * sin(Float(i) * 3.3), sin(a) * r])
    }
    return c.parts
  }

  func cabinPlant(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    c.cylinder(0.1, 0.055, slotHex(piece, 0), at: [0, 0.05, 0])
    for i in 0..<8 {
      let a = Float(i) / 8 * 2 * .pi
      let tilt: Float = 0.35 + Float(i % 3) * 0.12
      c.sphere(
        0.06, slotHex(piece, i.isMultiple(of: 2) ? 1 : 2),
        at: [cos(a) * 0.035, 0.17 + Float(i % 3) * 0.03, sin(a) * 0.035],
        scale: [0.35, 1.3, 0.12],
        turn: simd_quatf(angle: -a, axis: [0, 1, 0]) * simd_quatf(angle: -tilt, axis: [0, 0, 1]))
    }
    return c.parts
  }

  func cabinBasket(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    c.cylinder(0.08, 0.07, slotHex(piece, 0), at: [0, 0.04, 0])
    c.cylinder(0.082, 0.058, Self.hex(piece.slot(0).shaded(-0.3)), at: [0, 0.042, 0])
    c.sphere(0.03, slotHex(piece, 1), at: [-0.02, 0.09, 0])
    c.sphere(0.028, 0xF2D3A0, at: [0.025, 0.088, 0.015])
    c.sphere(0.026, slotHex(piece, 2), at: [0, 0.092, -0.03])
    return c.parts
  }

  func cabinBooks(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    c.box(
      0.12, 0.024, 0.09, r: 0.005, slotHex(piece, 0), at: [0, 0.012, 0],
      turn: simd_quatf(angle: 0.3, axis: [0, 1, 0]))
    c.box(
      0.1, 0.022, 0.08, r: 0.005, slotHex(piece, 1), at: [0, 0.035, 0],
      turn: simd_quatf(angle: 0.1, axis: [0, 1, 0]))
    return c.parts
  }

  /// The bed is drawn at this share of the Nooki project's size, as there.
  static let bedScale: Float = 0.78

  static func hex(_ colour: GenzColour) -> UInt32 {
    func channel(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
    return channel(colour.red) << 16 | channel(colour.green) << 8 | channel(colour.blue)
  }

  func cabinCatTree(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    let (rope, carpet, toy) = (slotHex(piece, 0), slotHex(piece, 1), slotHex(piece, 2))
    c.box(0.2, 0.03, 0.2, r: 0.012, carpet, at: [0, 0.015, 0])
    c.cylinder(0.32, 0.032, rope, at: [0, 0.18, 0])
    let ring = Self.hex(GenzColour(rope).shaded(-0.08))
    for y in stride(from: Float(0.05), to: 0.34, by: 0.025) {
      c.cylinder(0.006, 0.034, ring, at: [0, y, 0])
    }
    c.cylinder(0.03, 0.1, carpet, at: [0, 0.35, 0])
    c.cylinder(0.018, 0.075, toy, at: [0, 0.373, 0])
    c.cylinder(0.12, 0.002, NookiCabin.Tone.ink, at: [0.08, 0.28, 0.04])
    c.sphere(0.022, toy, at: [0.08, 0.21, 0.04])
    return c.parts
  }

  /// A nightstand with drawers, a candle whose flame flickers, and a small plant.
  func cabinNightstand(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    let (wood, drawers, leaf) = (slotHex(piece, 0), slotHex(piece, 1), slotHex(piece, 2))
    c.box(0.2, 0.2, 0.22, r: 0.012, wood, at: [0, 0.112, 0])
    for y: Float in [0.07, 0.155] {
      c.box(0.012, 0.072, 0.18, r: 0.004, drawers, at: [0.104, y, 0])
      c.sphere(0.01, NookiCabin.Tone.woodDark, at: [0.114, y, 0])
    }
    c.cylinder(0.06, 0.022, 0xFFF3E0, at: [-0.02, 0.242, 0.05])
    c.cylinder(0.06, 0.034, NookiCabin.Tone.pot, at: [0, 0.242, -0.06])
    let dark = Self.hex(GenzColour(leaf).shaded(-0.25))
    for i in 0..<6 {
      let a = Float(i) / 6 * 2 * .pi
      c.sphere(
        0.03, i.isMultiple(of: 2) ? leaf : dark,
        at: [cos(a) * 0.022, 0.3 + Float(i % 2) * 0.02, -0.06 + sin(a) * 0.022],
        scale: [0.55, 1.1, 0.55],
        turn: simd_quatf(angle: cos(a) * 0.5, axis: [0, 0, 1])
          * simd_quatf(angle: sin(a) * 0.5, axis: [1, 0, 0]))
    }
    // A teardrop of flame, named so the room flickers it.
    let flame = part(
      prism(sides: 8, radius: 0.011 * c.scale, top: 0.002 * c.scale, height: 0.032 * c.scale),
      glow(GenzColour(NookiCabin.Tone.flame)),
      at: c.origin + SIMD3<Float>(-0.02, 0.272, 0.05) * c.scale)
    flame.name = GenzRoom.flameName
    return c.parts + [flame]
  }

  /// A stool with a glowing lamp on it: the room's lamp, which a tap turns off and on.
  func cabinStoolLamp(_ piece: GenzPiece) -> [Entity] {
    var c = cabinClay(piece)
    let (wood, shade) = (slotHex(piece, 0), slotHex(piece, 1))
    c.box(0.11, 0.16, 0.11, r: 0.01, wood, at: [0, 0.08, 0])
    let dark = Self.hex(GenzColour(wood).shaded(-0.25))
    c.cylinder(0.012, 0.03, dark, at: [0, 0.166, 0])
    c.cylinder(0.07, 0.006, dark, at: [0, 0.2, 0])
    let lampShade = part(
      LowPoly.cylinder(height: 0.042 * c.scale, radius: 0.055 * c.scale, segments: 20),
      glow(GenzColour(shade)), at: c.origin + SIMD3<Float>(0, 0.255, 0) * c.scale)
    let bulb = Entity()
    bulb.name = GenzRoom.bulbName
    bulb.position = c.origin + SIMD3<Float>(-0.05, 0.3, 0.08) * c.scale
    return c.parts + [lampShade, bulb]
  }
}
