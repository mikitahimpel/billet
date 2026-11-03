import Foundation
import RealityKit

/// The pieces of the Window Seat room's furnished sets: a built-in seat under the window with a
/// linen cushion, leaning pillows and a folded knitted throw, a full bookshelf, a turned side
/// table, wall shelves, string lights, a knitted pouf, a cat bed and the small things lying
/// about. Wood carries a grain, fabric a weave or a knit, and ceramics a glaze.
@MainActor
extension GenzKit {
  // MARK: - The seat

  /// A built-in seat the width of the window: a panelled wooden base, a piped linen cushion
  /// level with the sill, pillows leaning on the glass and a knitted throw folded at one end,
  /// falling over the front.
  func windowBench(_ piece: GenzPiece) -> [Entity] {
    let length = GenzPiece.Kind.windowBench.size.x
    let oak = piece.slot(0)
    let wood = matte(oak, .wood, repeats: [4, 1])
    let woodDark = matte(oak.shaded(-0.28), .wood, repeats: [4, 1])
    let brass = glaze(GenzColour(0xC9A86A))
    var parts: [Entity] = [
      pad(0.1, 0.08, 0, length - 0.2, 1.34, 0.13, radius: 0.02, woodDark),
      pad(0, 0, 0.12, length, 1.52, 0.87, radius: 0.035, wood),
      pad(-0.04, 0, 0.98, length + 0.08, 1.6, 0.08, radius: 0.03, wood),
    ]
    let doors = 4
    let doorWidth = (length - 0.24) / Float(doors)
    let panel = matte(oak.shaded(0.1), .wood, repeats: [1, 1])
    for index in 0..<doors {
      let left = 0.12 + Float(index) * doorWidth
      parts.append(pad(left + 0.04, 1.5, 0.22, doorWidth - 0.08, 0.05, 0.68, radius: 0.02, wood))
      parts.append(
        pad(left + 0.17, 1.53, 0.34, doorWidth - 0.34, 0.04, 0.44, radius: 0.035, panel))
      parts.append(
        part(sphere(0.045), brass, at: GenzRoomPoint(left + doorWidth / 2, 1.58, 0.8).scene))
    }
    let linen = piece.slot(1)
    let cushionSize = SIMD3<Float>(length - 0.1, 0.24, 1.36)
    let cushionCentre = GenzRoomPoint(length / 2, 0.24 + cushionSize.z / 2, 1.18).scene
    parts.append(
      part(stuffed(cushionSize, .cushion, repeats: 10), matte(linen, .linen), at: cushionCentre))
    parts.append(
      part(
        tube("seat piping", piping(cushionSize, shape: .cushion), radius: 0.022, sides: 6),
        matte(linen.shaded(-0.12), .linen), at: cushionCentre))
    parts += pillows(piece)
    parts += foldedThrow(piece.slot(2), x: 0.22, near: 0.8, top: 1.3)
    return parts
  }

  /// The path round a stuffed thing's seam, slightly outside it.
  private func piping(_ size: SIMD3<Float>, shape: GenzStuffing) -> [SIMD3<Float>] {
    let half = size / 2
    let steps = 64
    return (0...steps).map { step in
      let angle = Float(step) / Float(steps) * 2 * .pi
      let c = cos(angle)
      let s = sin(angle)
      let power = 2 / shape.squareness
      let x = (c < 0 ? -1 : 1) * pow(abs(c), power)
      let z = (s < 0 ? -1 : 1) * pow(abs(s), power)
      let pullX = 1 - shape.pinch * (1 - z * z)
      let pullZ = 1 - shape.pinch * (1 - x * x)
      return [x * half.x * pullX, 0, z * half.z * pullZ]
    }
  }

  /// Pillows standing on the cushion and leaning back on the glass, each its own fabric.
  private func pillows(_ piece: GenzPiece) -> [Entity] {
    let specs:
      [(x: Float, width: Float, height: Float, colour: GenzColour, knit: Bool, roll: Float)] = [
        (1.45, 1.2, 1.0, piece.slot(1).shaded(0.35), true, 0.07),
        (2.62, 1.05, 0.9, GenzColour(0xC2603F), false, -0.05),
        (3.66, 0.95, 0.84, GenzColour(0x8FA67E), false, 0.09),
        (4.5, 0.74, 0.68, piece.slot(2), true, -0.12),
      ]
    let lean: Float = 0.22
    let thickness: Float = 0.34
    return specs.map { spec in
      let mesh = stuffed([spec.width, thickness, spec.height], .pillow, repeats: 2)
      let material =
        spec.knit
        ? matte(spec.colour, .knit, repeats: [2.5, 2.5])
        : matte(spec.colour, .linen, repeats: [3, 3])
      let up = spec.height / 2
      let centre = GenzRoomPoint(
        spec.x, 0.48 - up * sin(lean), 1.26 + up * cos(lean))
      return part(
        mesh, material, at: centre.scene,
        turn: simd_quatf(angle: spec.roll, axis: [0, 0, 1])
          * simd_quatf(angle: -.pi / 2 - lean, axis: [1, 0, 0]))
    }
  }

  /// A chunky throw folded in three on the seat, its last fold falling over the front edge
  /// with tassels.
  private func foldedThrow(_ colour: GenzColour, x: Float, near: Float, top: Float) -> [Entity] {
    let knit = matte(colour, .knit, repeats: [3, 2])
    let shade = matte(colour.shaded(-0.12), .knit, repeats: [3, 2])
    let width: Float = 1.3
    var parts: [Entity] = []
    let layers: [(lift: Float, shift: Float, turn: Float)] = [
      (0.04, 0, 0), (0.12, 0.03, 0.04), (0.2, -0.02, -0.03),
    ]
    for (index, layer) in layers.enumerated() {
      parts.append(
        part(
          stuffed([width, 0.1, 0.78], .cloth, repeats: 2), index == 1 ? shade : knit,
          at: GenzRoomPoint(x + width / 2 + layer.shift, near + 0.4, top + layer.lift).scene,
          turn: simd_quatf(angle: layer.turn, axis: [0, 1, 0])))
    }
    let front: Float = 1.6
    let drop: Float = 0.62
    let drape = cached("throw drape") {
      var mesh = GenzSmooth()
      mesh.grid(columns: 24, rows: 8, repeats: [3, 1]) { u, v in
        let fold = 0.035 * sin(u * .pi * 6) * v
        let bulge = 0.05 * sin(v * .pi)
        return GenzRoomPoint(
          u * width, front + 0.05 + bulge + fold, top - 0.02 - v * drop
        ).scene
      }
      return mesh.mesh("drape")
    }
    var hanging = knit
    hanging.faceCulling = .none
    parts.append(part(drape, hanging, at: GenzRoomPoint(x, 0, 0).scene))
    parts.append(
      part(
        tube(
          "throw roll",
          [
            GenzRoomPoint(0, front - 0.02, top).scene,
            GenzRoomPoint(width, front - 0.02, top).scene,
          ],
          radius: 0.07, sides: 10),
        knit, at: GenzRoomPoint(x, 0, 0).scene))
    var tassels: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for step in stride(from: Float(0.08), to: width, by: 0.13) {
      tassels.append(
        (
          GenzRoomPoint(step, front + 0.06 + 0.035 * sin(step / width * .pi * 6), top - drop - 0.06)
            .scene, [0.035, 0.1, 0.035]
        ))
    }
    parts.append(part(boxes("throw tassels", tassels), shade, at: GenzRoomPoint(x, 0, 0).scene))
    return parts
  }

  /// A knitted cardigan dropped on the seat, one sleeve hanging over the edge.
  func cardigan(_ piece: GenzPiece) -> [Entity] {
    let knit = matte(piece.slot(0), .knit, repeats: [4, 4])
    let rib = matte(piece.slot(0).shaded(-0.14), .knit, repeats: [6, 1])
    let button = glaze(piece.slot(1))
    var parts: [Entity] = [
      part(
        stuffed([1.0, 0.12, 0.78], .cloth, repeats: 3), knit,
        at: GenzRoomPoint(0.6, 0.5, 0.04).scene, turn: simd_quatf(angle: 0.12, axis: [0, 1, 0])),
      part(
        stuffed([0.62, 0.09, 0.5], .cloth, repeats: 2), rib,
        at: GenzRoomPoint(0.48, 0.42, 0.09).scene, turn: simd_quatf(angle: -0.2, axis: [0, 1, 0])),
    ]
    let hanging = [
      GenzRoomPoint(1.0, 0.55, 0.07), GenzRoomPoint(1.2, 0.85, 0.08),
      GenzRoomPoint(1.28, 1.12, 0.08),
      GenzRoomPoint(1.32, 1.3, 0.03), GenzRoomPoint(1.34, 1.38, -0.09),
      GenzRoomPoint(1.35, 1.39, -0.2),
    ].map(\.scene)
    parts.append(part(tube("cardigan sleeve", hanging, radius: 0.08, sides: 10), knit))
    parts.append(
      part(
        prism(sides: 10, radius: 0.085, top: 0.085, height: 0.09, turn: 0), rib,
        at: GenzRoomPoint(1.35, 1.39, -0.28).scene))
    let folded = [
      GenzRoomPoint(0.18, 0.3, 0.08), GenzRoomPoint(0.35, 0.62, 0.12),
      GenzRoomPoint(0.7, 0.78, 0.12),
      GenzRoomPoint(0.95, 0.8, 0.09),
    ].map(\.scene)
    parts.append(part(tube("cardigan arm", folded, radius: 0.075, sides: 10), knit))
    for index in 0..<4 {
      let along = Float(index) * 0.15
      parts.append(
        part(sphere(0.025), button, at: GenzRoomPoint(0.72 + along * 0.2, 0.25 + along, 0.12).scene)
      )
    }
    return parts
  }

  // MARK: - Books and shelves

  /// A tall open bookshelf, its shelves full of books of every height and colour, with a vase, a
  /// small plant, a photo and a candle among them.
  func bookshelf(_ piece: GenzPiece) -> [Entity] {
    let size = GenzPiece.Kind.bookshelf.size
    let oak = piece.slot(0)
    let wood = matte(oak, .wood, repeats: [1, 4])
    let woodDark = matte(oak.shaded(-0.3), .wood, repeats: [1, 4])
    var parts: [Entity] = [
      pad(0, 0, 0, 0.07, 0.58, size.z - 0.06, radius: 0.02, wood),
      pad(size.x - 0.07, 0, 0, 0.07, 0.58, size.z - 0.06, radius: 0.02, wood),
      block(0.07, 0, 0.1, size.x - 0.14, 0.03, size.z - 0.2, woodDark),
      pad(-0.04, 0, size.z - 0.08, size.x + 0.08, 0.62, 0.08, radius: 0.03, wood),
      pad(0.07, 0.05, 0, size.x - 0.14, 0.5, 0.12, radius: 0.015, woodDark),
    ]
    let shelves: [Float] = [0.12, 0.78, 1.44, 2.1, 2.76]
    for z in shelves {
      parts.append(pad(0.06, 0.03, z, size.x - 0.12, 0.55, 0.05, radius: 0.015, wood))
    }
    let colours: [GenzColour] = [
      piece.slot(1), piece.slot(2), GenzColour(0xEFE4D0), GenzColour(0xD9A441),
      GenzColour(0x4F6B8A), GenzColour(0xD49A86), piece.slot(1).shaded(-0.3), GenzColour(0x6E5A7E),
    ]
    var books = [[(centre: SIMD3<Float>, size: SIMD3<Float>)]](repeating: [], count: colours.count)
    var bands: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    var random = GenzRandom(seed: 7)
    /// A row of upright books from `start` to `end` on the shelf at `floor`.
    func row(_ start: Float, _ end: Float, floor: Float, tallest: Float) -> Float {
      var left = start
      while true {
        let width = random.next(0.06, 0.13)
        guard left + width <= end else { break }
        let height = random.next(tallest * 0.72, tallest)
        let depth = random.next(0.36, 0.44)
        let colour = random.index(colours.count)
        let centre = GenzRoomPoint(left + width / 2, 0.52 - depth / 2, floor + height / 2).scene
        books[colour].append((centre, [width, height, depth]))
        if random.next(0, 1) < 0.55 {
          for share: Float in [0.16, 0.8] {
            bands.append(
              (
                GenzRoomPoint(left + width / 2, 0.522, floor + height * share).scene,
                [width * 0.86, 0.022, 0.006]
              ))
          }
        }
        left += width + 0.004
      }
      return left
    }
    let floors = shelves.map { $0 + 0.05 }
    _ = row(0.1, size.x - 0.09, floor: floors[0], tallest: 0.56)
    let after = row(0.1, 0.98, floor: floors[1], tallest: 0.54)
    parts.append(
      vase(at: GenzRoomPoint(max(after, 1.0) + 0.22, 0.3, floors[1]), colour: GenzColour(0x8FA67E)))
    for (index, height) in [Float(0.07), 0.06, 0.08, 0.05].enumerated() {
      let below = [Float(0), 0.07, 0.13, 0.21][index]
      let width = 0.5 - Float(index) * 0.04
      books[(index * 3) % colours.count].append(
        (GenzRoomPoint(0.38, 0.3, floors[2] + below + height / 2).scene, [width, height, 0.38]))
    }
    let end = row(0.68, size.x - 0.2, floor: floors[2], tallest: 0.52)
    let leaning = part(box([0.1, 0.5, 0.4]), matte(colours[4]))
    leaning.position = GenzRoomPoint(end + 0.14, 0.3, floors[2] + 0.24).scene
    leaning.orientation = simd_quatf(angle: -0.3, axis: [0, 0, 1])
    parts.append(leaning)
    parts += pottedSprig(at: GenzRoomPoint(0.33, 0.3, floors[3]), colour: piece.slot(2))
    _ = row(0.62, 1.3, floor: floors[3], tallest: 0.5)
    parts += candle(at: GenzRoomPoint(1.42, 0.3, floors[3]), height: 0.16)
    _ = row(0.1, 0.72, floor: floors[4], tallest: 0.44)
    parts += photoFrame(at: GenzRoomPoint(1.02, 0.25, floors[4]))
    parts.append(
      vase(at: GenzRoomPoint(1.38, 0.3, floors[4]), colour: GenzColour(0xD49A86), small: true))
    for (index, group) in books.enumerated() where !group.isEmpty {
      parts.append(part(boxes("shelf books \(index)", group), matte(colours[index])))
    }
    parts.append(part(boxes("shelf bands", bands), matte(GenzColour(0xE8C987))))
    return parts
  }

  /// A small glazed vase standing at `point`.
  private func vase(at point: GenzRoomPoint, colour: GenzColour, small: Bool = false) -> Entity {
    let profile: [SIMD2<Float>] =
      small
      ? [
        [0, 0], [0.05, 0], [0.07, 0.04], [0.075, 0.09], [0.05, 0.15], [0.035, 0.17], [0.04, 0.19],
        [0, 0.18],
      ]
      : [
        [0, 0], [0.07, 0], [0.1, 0.06], [0.11, 0.16], [0.08, 0.27], [0.045, 0.32], [0.05, 0.36],
        [0, 0.34],
      ]
    return part(
      lathe(small ? "vase small" : "vase", profile, sides: 18), glaze(colour), at: point.scene)
  }

  /// A small pot with a sprig of round leaves, standing at `point`.
  private func pottedSprig(at point: GenzRoomPoint, colour: GenzColour) -> [Entity] {
    let pot: [SIMD2<Float>] = [
      [0, 0], [0.08, 0], [0.1, 0.13], [0.11, 0.15], [0.095, 0.15], [0, 0.14],
    ]
    var parts: [Entity] = [
      part(lathe("sprig pot", pot, sides: 16), glaze(GenzColour(0xE9DCC6)), at: point.scene)
    ]
    let leaf = matte(colour.shaded(-0.1))
    let spots: [SIMD3<Float>] = [
      [0, 0.24, 0], [0.07, 0.2, 0.03], [-0.06, 0.21, -0.02], [0.02, 0.29, -0.04],
      [-0.03, 0.18, 0.06],
    ]
    for spot in spots {
      let model = part(
        stuffed([0.09, 0.025, 0.07], .pillow, detail: 5), leaf, at: point.scene + spot)
      model.orientation = simd_quatf(angle: spot.x * 8, axis: [0, 0, 1])
      parts.append(model)
    }
    return parts
  }

  /// A pillar candle with a lit flame, standing at `point`.
  private func candle(at point: GenzRoomPoint, height: Float, radius: Float = 0.055) -> [Entity] {
    let wax: [SIMD2<Float>] = [
      [0, 0], [radius, 0], [radius, height - 0.012], [radius - 0.012, height],
      [radius * 0.5, height - 0.01], [0, height - 0.012],
    ]
    let flame: [SIMD2<Float>] = [
      [0, 0], [0.018, 0.015], [0.016, 0.035], [0.006, 0.06], [0, 0.07],
    ]
    let flameModel = part(
      lathe("flame", flame, sides: 10), glow(GenzColour(0xFFC870)),
      at: point.scene + [0, height + 0.005, 0])
    flameModel.name = GenzRoom.flameName
    return [
      part(lathe("candle \(height) \(radius)", wax, sides: 16), waxMaterial, at: point.scene),
      part(
        box([0.006, 0.03, 0.006]), matte(GenzColour(0x2A2421)), at: point.scene + [0, height, 0]),
      flameModel,
    ]
  }

  private var waxMaterial: PhysicallyBasedMaterial {
    var material = matte(GenzColour(0xF3E8D6))
    material.roughness = 0.55
    material.emissiveColor = .init(color: GenzColour(0xFFB860).platformColour)
    material.emissiveIntensity = 0.12
    return material
  }

  /// A framed photo leaning back at `point`.
  private func photoFrame(at point: GenzRoomPoint) -> [Entity] {
    let holder = Entity()
    holder.position = point.scene + [0, 0.15, 0]
    holder.orientation = simd_quatf(angle: -0.18, axis: [1, 0, 0])
    holder.addChild(part(roundBox([0.26, 0.31, 0.03], radius: 0.008), matte(GenzColour(0x3B2A20))))
    holder.addChild(part(box([0.2, 0.25, 0.006]), matte(GenzColour(0xF4EFE6)), at: [0, 0, 0.015]))
    holder.addChild(
      part(box([0.15, 0.15, 0.004]), matte(GenzColour(0xE9A07A)), at: [0, 0.03, 0.019]))
    return [holder]
  }

  /// Two floating shelves with a trailing plant, candles, books, a vase of dried grass and a
  /// cactus.
  func wallShelves(_ piece: GenzPiece) -> [Entity] {
    let wood = matte(piece.slot(0), .wood, repeats: [2, 1])
    let metal = matte(GenzColour(0x2A2421))
    var parts: [Entity] = []
    for z: Float in [0, 0.66] {
      parts.append(pad(0, 0, z, 1.4, 0.32, 0.05, radius: 0.015, wood))
      for x: Float in [0.22, 1.14] { parts.append(block(x, 0, z - 0.1, 0.04, 0.2, 0.1, metal)) }
    }
    let lower: Float = 0.05
    let upper: Float = 0.71
    let pot: [SIMD2<Float>] = [
      [0, 0], [0.09, 0], [0.11, 0.14], [0.12, 0.16], [0.105, 0.16], [0, 0.15],
    ]
    parts.append(
      part(
        lathe("trailing pot", pot, sides: 16), glaze(piece.slot(1)),
        at: GenzRoomPoint(0.3, 0.17, lower).scene))
    let vine = [
      GenzRoomPoint(0.36, 0.22, lower + 0.15), GenzRoomPoint(0.42, 0.3, lower + 0.08),
      GenzRoomPoint(0.44, 0.34, lower - 0.1),
      GenzRoomPoint(0.4, 0.34, lower - 0.3), GenzRoomPoint(0.45, 0.33, lower - 0.48),
    ].map(\.scene)
    let leafGreen = matte(GenzColour(0x5E8F4E))
    parts.append(part(tube("vine", vine, radius: 0.008, sides: 5), leafGreen))
    for (index, point) in vine.enumerated() {
      let leaf = part(
        stuffed([0.08, 0.02, 0.065], .pillow, detail: 5),
        index.isMultiple(of: 2) ? leafGreen : matte(GenzColour(0x7FA65E)),
        at: point + [0.02, -0.02, 0.02])
      leaf.orientation = simd_quatf(angle: 1.2 + Float(index) * 0.5, axis: [0, 0, 1])
      parts.append(leaf)
    }
    let topLeaves: [SIMD3<Float>] = [[0.24, 0.24, 0.17], [0.32, 0.26, 0.1], [0.28, 0.22, 0.22]]
    for spot in topLeaves {
      parts.append(
        part(
          stuffed([0.1, 0.025, 0.08], .pillow, detail: 5), leafGreen,
          at: GenzRoomPoint(spot.x, spot.z, lower + spot.y).scene))
    }
    parts += candle(at: GenzRoomPoint(0.78, 0.16, lower), height: 0.2)
    parts += candle(at: GenzRoomPoint(0.92, 0.18, lower), height: 0.13, radius: 0.045)
    parts.append(
      pad(1.05, 0.06, lower, 0.3, 0.22, 0.05, radius: 0.01, matte(GenzColour(0xC2603F), .linen)))
    parts.append(
      pad(
        1.07, 0.07, lower + 0.05, 0.26, 0.2, 0.045, radius: 0.01,
        matte(GenzColour(0xEFE4D0), .linen)))
    parts.append(vase(at: GenzRoomPoint(0.3, 0.16, upper), colour: piece.slot(2)))
    let grass = matte(GenzColour(0xE7D3B0))
    for (index, lean) in [Float(-0.25), 0.05, 0.3].enumerated() {
      let base = GenzRoomPoint(0.3, 0.16, upper + 0.3).scene
      let top = base + SIMD3(sin(lean) * 0.4, cos(lean) * 0.4, Float(index - 1) * 0.04)
      parts.append(part(tube("grass stem \(index)", [base, top], radius: 0.005, sides: 4), grass))
      let fluff: [SIMD2<Float>] = [
        [0, 0], [0.03, 0.03], [0.05, 0.1], [0.045, 0.18], [0.02, 0.24], [0, 0.26],
      ]
      let plume = part(
        lathe("plume", fluff, sides: 10, repeats: 3),
        matte(GenzColour(0xEBDCC0), .knit, repeats: [3, 3]),
        at: top - simd_normalize(top - base) * 0.04)
      plume.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(top - base))
      parts.append(plume)
    }
    parts += photoFrame(at: GenzRoomPoint(0.8, 0.12, upper))
    let cactusPot: [SIMD2<Float>] = [[0, 0], [0.06, 0], [0.07, 0.1], [0, 0.1]]
    parts.append(
      part(
        lathe("cactus pot", cactusPot, sides: 12), glaze(GenzColour(0xE9DCC6)),
        at: GenzRoomPoint(1.15, 0.16, upper).scene))
    let cactus: [SIMD2<Float>] = [[0, 0], [0.045, 0], [0.05, 0.08], [0.04, 0.15], [0, 0.17]]
    parts.append(
      part(
        lathe("cactus", cactus, sides: 8), matte(GenzColour(0x4F7F45)),
        at: GenzRoomPoint(1.15, 0.16, upper + 0.09).scene))
    return parts
  }

  /// Warm bulbs on a wire, hanging in swags between pins.
  func stringLights(_ piece: GenzPiece) -> [Entity] {
    let length = GenzPiece.Kind.stringLights.size.x
    let pins: [Float] = stride(from: 0, through: length, by: length / 4).map { $0 }
    var wire: [SIMD3<Float>] = []
    var bulbs: [SIMD3<Float>] = []
    let top: Float = 0.5
    for (start, end) in zip(pins, pins.dropFirst()) {
      let swag = Self.hanging(
        from: GenzRoomPoint(start, 0.04, top).scene, to: GenzRoomPoint(end, 0.04, top).scene,
        sag: 0.34,
        steps: 12)
      wire += wire.isEmpty ? swag : Array(swag.dropFirst())
      for step in 1..<6 { bulbs.append(swag[step * 2] + [0, -0.04, 0.012]) }
    }
    return [
      part(tube("light wire", wire, radius: 0.007, sides: 5), matte(piece.slot(0))),
      part(beads("light bulbs", bulbs, radius: 0.034), glow(piece.slot(1))),
      part(
        beads("light pins", pins.map { GenzRoomPoint($0, 0.02, top).scene }, radius: 0.02),
        matte(piece.slot(0))),
    ]
  }

  /// Small balls at `centres`, as one mesh.
  func beads(_ name: String, _ centres: [SIMD3<Float>], radius: Float) -> MeshResource {
    cached("beads \(name)") {
      var mesh = GenzSmooth()
      for centre in centres {
        mesh.grid(columns: 8, rows: 6) { u, v in
          let around = u * 2 * .pi
          let down = v * .pi
          return centre + SIMD3(cos(around) * sin(down), cos(down), sin(around) * sin(down))
            * radius
        }
      }
      return mesh.mesh(name)
    }
  }

  // MARK: - Tables and soft seats

  /// A round side table on three splayed legs, with a lower shelf holding magazines.
  func sideTable(_ piece: GenzPiece) -> [Entity] {
    let wood = matte(piece.slot(0), .wood, repeats: [2, 1])
    let centre = GenzRoomPoint(0.5, 0.5, 0).scene
    let top: [SIMD2<Float>] = [
      [0, 0.86], [0.43, 0.86], [0.46, 0.87], [0.47, 0.89], [0.46, 0.915], [0.44, 0.92], [0, 0.92],
    ]
    let shelf: [SIMD2<Float>] = [
      [0, 0.3], [0.33, 0.3], [0.345, 0.315], [0.33, 0.33], [0, 0.33],
    ]
    var parts: [Entity] = [
      part(lathe("table top", top, sides: 32), wood, at: centre),
      part(lathe("table shelf", shelf, sides: 28), wood, at: centre),
    ]
    for index in 0..<3 {
      let angle = Float(index) * 2 * .pi / 3 + 0.5
      let direction = SIMD3<Float>(cos(angle), 0, sin(angle))
      let leg = [direction * 0.4, direction * 0.3 + [0, 0.87, 0]]
      parts.append(part(tube("table leg \(index)", leg, radius: 0.032, sides: 8), wood, at: centre))
    }
    parts.append(
      part(
        roundBox([0.36, 0.03, 0.27], radius: 0.008), matte(piece.slot(1)),
        at: centre + [0.02, 0.345, 0.03],
        turn: simd_quatf(angle: 0.3, axis: [0, 1, 0])))
    parts.append(
      part(
        roundBox([0.34, 0.025, 0.25], radius: 0.008), matte(GenzColour(0xEFE4D0)),
        at: centre + [-0.01, 0.372, 0],
        turn: simd_quatf(angle: -0.15, axis: [0, 1, 0])))
    return parts
  }

  /// A round knitted pouf with a button sunk in its top.
  func knitPouf(_ piece: GenzPiece) -> [Entity] {
    let centre = GenzRoomPoint(0.45, 0.45, 0).scene
    let profile: [SIMD2<Float>] = [
      [0, 0], [0.36, 0], [0.43, 0.04], [0.46, 0.12], [0.47, 0.25], [0.46, 0.38], [0.42, 0.46],
      [0.32, 0.5], [0.12, 0.5], [0, 0.47],
    ]
    return [
      part(
        lathe("pouf", profile, sides: 28, repeats: 7),
        matte(piece.slot(0), .knit, repeats: [7, 2]), at: centre),
      part(sphere(0.04), matte(piece.slot(1)), at: centre + [0, 0.48, 0]),
    ]
  }

  /// A round cat bed: a fleecy rim round a soft base, with a little blanket and a ball of yarn.
  func catBed(_ piece: GenzPiece) -> [Entity] {
    let centre = GenzRoomPoint(0.5, 0.5, 0).scene
    let fleece = matte(piece.slot(0), .linen, repeats: [8, 2])
    var rim: [SIMD2<Float>] = []
    for step in 0...14 {
      let angle = Float(step) / 14 * 2 * .pi - .pi / 2
      rim.append([0.37 + cos(angle) * 0.12, 0.13 + sin(angle) * 0.12])
    }
    let base: [SIMD2<Float>] = [[0, 0], [0.4, 0], [0.42, 0.04], [0.38, 0.09], [0, 0.1]]
    return [
      part(lathe("cat bed rim", rim.reversed(), sides: 28, repeats: 10), fleece, at: centre),
      part(lathe("cat bed base", base, sides: 24), fleece, at: centre),
      part(
        stuffed([0.42, 0.06, 0.34], .cloth, detail: 10),
        matte(piece.slot(1), .knit, repeats: [2, 2]),
        at: centre + [-0.04, 0.12, 0.03], turn: simd_quatf(angle: 0.4, axis: [0, 1, 0])),
      part(
        sphere(0.07), matte(piece.slot(1).shaded(-0.2), .knit, repeats: [3, 3]),
        at: centre + [0.16, 0.16, -0.1]),
    ]
  }

  /// Three pillar candles on a glazed dish.
  func candles(_ piece: GenzPiece) -> [Entity] {
    let dish: [SIMD2<Float>] = [
      [0, 0], [0.18, 0], [0.22, 0.03], [0.21, 0.035], [0.17, 0.012], [0, 0.012],
    ]
    var parts: [Entity] = [
      part(
        lathe("candle dish", dish, sides: 24), glaze(piece.slot(1)),
        at: GenzRoomPoint(0.25, 0.2, 0).scene)
    ]
    parts += candle(at: GenzRoomPoint(0.17, 0.17, 0.012), height: 0.26, radius: 0.06)
    parts += candle(at: GenzRoomPoint(0.33, 0.15, 0.012), height: 0.18, radius: 0.055)
    parts += candle(at: GenzRoomPoint(0.27, 0.3, 0.012), height: 0.11, radius: 0.05)
    return parts
  }
}

/// A small repeatable stream of numbers, so a shelf of books comes out the same every time.
struct GenzRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

  mutating func next(_ low: Float, _ high: Float) -> Float {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    let share = Float(state >> 40) / Float(1 << 24)
    return low + (high - low) * share
  }

  mutating func index(_ count: Int) -> Int { min(Int(next(0, Float(count))), count - 1) }
}
