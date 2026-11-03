import Foundation
import RealityKit

/// The pieces of the furnished sets: softer, more detailed low-poly furniture with quilting,
/// knitted folds, pleats and small props. Each keeps to the same rules as the first pieces: room
/// units, the near floor corner at the origin, and one material per part from the piece's slots.
@MainActor
extension GenzKit {
  /// A box with rounded edges, in the terms of ``block(_:_:_:_:_:_:_:)``.
  func pad(
    _ x: Float, _ y: Float, _ z: Float, _ w: Float, _ d: Float, _ h: Float, radius: Float,
    _ material: any RealityKit.Material
  ) -> ModelEntity {
    return part(
      softBox([w, h, d], radius: radius), material,
      at: GenzRoomPoint(x + w / 2, y + d / 2, z + h / 2).scene)
  }

  func sphere(_ radius: Float) -> MeshResource { ball(radius) }

  // MARK: - Beds

  /// A low daybed under the window: a wooden frame on short legs, a quilted mattress, cushions
  /// leaning on the wall and a knitted throw folded over one end.
  func quiltedDaybed(_ piece: GenzPiece) -> [Entity] {
    let frame = matte(piece.slot(0))
    var parts: [Entity] = []
    for x: Float in [0.15, 6.29] {
      for y: Float in [0.15, 2.09] { parts.append(block(x, y, 0, 0.16, 0.16, 0.2, frame)) }
    }
    parts.append(pad(0, 0, 0.2, 6.6, 2.4, 0.26, radius: 0.05, frame))
    parts.append(pad(0.08, 0.06, 0.44, 6.44, 2.28, 0.36, radius: 0.14, matte(piece.slot(1))))
    parts += quilting("daybed", x: 0.3, y: 0.2, w: 3.1, d: 2.0, z: 0.8, colour: piece.slot(1))
    let cushions: [(x: Float, w: Float, colour: GenzColour)] = [
      (0.3, 1.35, piece.slot(1).shaded(0.45)), (1.75, 1.2, piece.slot(2).shaded(0.25)),
      (3.0, 1.0, piece.slot(0).shaded(0.45)),
    ]
    for cushion in cushions {
      let model = part(
        roundBox([cushion.w, 0.8, 0.42], radius: 0.18), matte(cushion.colour),
        at: GenzRoomPoint(cushion.x + cushion.w / 2, 0.36, 1.18).scene,
        turn: simd_quatf(angle: -0.28, axis: [1, 0, 0]))
      let button = part(
        sphere(0.035), matte(cushion.colour.shaded(-0.3)), at: [0, 0.02, 0.21])
      model.addChild(button)
      parts.append(model)
    }
    parts += knittedThrow(
      "daybed", x: 3.5, y: 0.42, w: 2.9, depth: 1.95, top: 0.8, drop: 0.55, colour: piece.slot(2))
    return parts
  }

  /// A low bed with pillows, a quilted duvet and a knitted throw across its foot.
  func quiltedBed(_ piece: GenzPiece) -> [Entity] {
    let frame = matte(piece.slot(0))
    var parts: [Entity] = []
    for x: Float in [0.1, 4.54] {
      for y: Float in [0.1, 3.14] { parts.append(block(x, y, 0, 0.16, 0.16, 0.16, frame)) }
    }
    parts.append(pad(0, 0, 0.16, 4.8, 3.4, 0.28, radius: 0.06, frame))
    parts.append(block(0, -0.05, 0.16, 4.8, 0.14, 1.05, frame))
    parts.append(pad(0.1, 0.1, 0.44, 4.6, 3.24, 0.38, radius: 0.14, matte(piece.slot(1))))
    for x: Float in [0.35, 2.55] {
      parts.append(
        pad(x, 0.2, 0.8, 1.9, 0.8, 0.3, radius: 0.13, matte(piece.slot(1).shaded(0.35))))
    }
    let duvet = piece.slot(1).shaded(-0.06)
    parts.append(pad(0.05, 1.15, 0.8, 4.7, 2.25, 0.16, radius: 0.07, matte(duvet)))
    parts += quilting("bed", x: 0.25, y: 1.25, w: 4.3, d: 1.0, z: 0.96, colour: duvet)
    parts += knittedThrow(
      "bed", x: 0.35, y: 2.3, w: 4.1, depth: 1.08, top: 0.96, drop: 0.6, colour: piece.slot(2))
    return parts
  }

  /// Raised squares with a button at each corner, sewn into a cover.
  private func quilting(
    _ name: String, x: Float, y: Float, w: Float, d: Float, z: Float, colour: GenzColour
  ) -> [Entity] {
    let cell: Float = 0.5
    let columns = Int(w / cell)
    let rows = Int(d / cell)
    var squares: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    var buttons: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for column in 0..<columns {
      for row in 0..<rows {
        let left = x + Float(column) * cell
        let near = y + Float(row) * cell
        squares.append(
          (GenzRoomPoint(left + cell / 2, near + cell / 2, z + 0.02).scene, [0.44, 0.04, 0.44]))
        buttons.append((GenzRoomPoint(left, near, z + 0.03).scene, [0.05, 0.04, 0.05]))
      }
    }
    return [
      part(boxes("quilt \(name)", squares), matte(colour.shaded(0.12))),
      part(boxes("quilt buttons \(name)", buttons), matte(colour.shaded(-0.28))),
    ]
  }

  /// A chunky knitted blanket: flat over the top with ribs along it, rolled at the edge, and
  /// falling over the front in soft folds.
  private func knittedThrow(
    _ name: String, x: Float, y: Float, w: Float, depth: Float, top: Float, drop: Float,
    colour: GenzColour
  ) -> [Entity] {
    let knit = matte(colour)
    let shade = matte(colour.shaded(-0.14))
    var parts: [Entity] = [pad(x, y, top, w, depth, 0.07, radius: 0.03, knit)]
    var ribs: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for step in stride(from: x + 0.1, to: x + w - 0.05, by: 0.18) {
      ribs.append((GenzRoomPoint(step, y + depth / 2, top + 0.075).scene, [0.07, 0.025, depth]))
    }
    parts.append(part(boxes("knit \(name)", ribs), shade))
    let front = y + depth
    parts.append(pad(x, front - 0.06, top - 0.04, w, 0.16, 0.16, radius: 0.07, knit))
    let folds = max(Int(w / 0.42), 2)
    let width = w / Float(folds)
    for index in 0..<folds {
      let out: Float = index.isMultiple(of: 2) ? 0.1 : 0.04
      let fold = part(
        roundBox([width + 0.04, drop, 0.08], radius: 0.035),
        index.isMultiple(of: 2) ? knit : shade,
        at: GenzRoomPoint(x + width * (Float(index) + 0.5), front + out, top + 0.02 - drop / 2)
          .scene,
        turn: simd_quatf(angle: index.isMultiple(of: 2) ? 0.1 : -0.1, axis: [0, 1, 0])
          * simd_quatf(angle: 0.06, axis: [1, 0, 0]))
      parts.append(fold)
    }
    var tassels: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for step in stride(from: x + 0.12, to: x + w, by: 0.24) {
      tassels.append(
        (GenzRoomPoint(step, front + 0.08, top - drop - 0.04).scene, [0.04, 0.1, 0.04]))
    }
    parts.append(part(boxes("tassels \(name)", tassels), shade))
    return parts
  }

  func roundBox(_ size: SIMD3<Float>, radius: Float) -> MeshResource {
    softBox(size, radius: radius)
  }

  // MARK: - Storage and lamps

  /// A wooden crate on its side as a shelf, open to the front, full of books.
  func bookCrate(_ piece: GenzPiece) -> [Entity] {
    let wood = matte(piece.slot(0))
    var parts: [Entity] = [
      block(0.06, 0, 0.06, 0.78, 0.05, 0.78, matte(piece.slot(0).shaded(-0.15))),
      block(0, 0, 0, 0.9, 0.9, 0.06, wood),
      block(0, 0, 0.84, 0.9, 0.9, 0.06, wood),
    ]
    for z: Float in [0.06, 0.33, 0.6] {
      parts.append(block(0, 0, z, 0.06, 0.9, 0.22, wood))
      parts.append(block(0.84, 0, z, 0.06, 0.9, 0.22, wood))
    }
    let colours = [
      piece.slot(1), piece.slot(2), piece.slot(1).shaded(0.35), GenzColour(0xEFE4D0),
      piece.slot(2).shaded(-0.2), piece.slot(1).shaded(-0.2),
    ]
    let books: [(width: Float, height: Float)] = [
      (0.1, 0.62), (0.08, 0.7), (0.12, 0.56), (0.09, 0.66), (0.11, 0.6), (0.08, 0.5),
    ]
    var left: Float = 0.08
    for (index, book) in books.enumerated() {
      parts.append(
        block(left, 0.12, 0.06, book.width, 0.62, book.height, matte(colours[index])))
      left += book.width + 0.005
    }
    let leaning = block(0, 0, 0, 0.09, 0.6, 0.58, matte(colours[3]))
    leaning.position = GenzRoomPoint(left + 0.17, 0.43, 0.34).scene
    leaning.orientation = simd_quatf(angle: -0.38, axis: [0, 0, 1])
    parts.append(leaning)
    return parts
  }

  /// A brass lamp with a pleated cone shade and a warm bulb showing under it. The bulb is named
  /// for the lamp light.
  func pleatedLamp(_ piece: GenzPiece) -> [Entity] {
    let brass = matte(piece.slot(0))
    let centre = GenzRoomPoint(0.5, 0.5, 0).scene
    let bulb = Entity()
    bulb.name = GenzRoom.bulbName
    bulb.position = centre + [0, 0.62, 0]
    let glass = part(sphere(0.09), glow(GenzColour(0xFFF1D0)), at: centre + [0, 0.6, 0])
    glass.name = GenzRoom.bulbGlassName
    let shadeBottom: Float = 0.52
    let sides = 20
    let body: [SIMD2<Float>] = [
      [0, 0], [0.11, 0], [0.14, 0.02], [0.17, 0.1], [0.175, 0.18], [0.15, 0.27], [0.09, 0.33],
      [0.05, 0.35], [0.05, 0.37], [0, 0.37],
    ]
    var parts: [Entity] = [
      part(lathe("lamp body", body, sides: 24), glaze(GenzColour(0xA9BFA4)), at: centre),
      part(
        prism(sides: 10, radius: 0.025, top: 0.025, height: 0.2), brass, at: centre + [0, 0.36, 0]),
      glass,
      part(
        prism(sides: sides, radius: 0.48, top: 0.28, height: 0.48, turn: 0),
        glow(piece.slot(1)), at: centre + [0, shadeBottom, 0]),
      part(sphere(0.04), brass, at: centre + [0, shadeBottom + 0.52, 0]),
      bulb,
    ]
    let pleat = glow(piece.slot(1).shaded(-0.12))
    for index in 0..<sides {
      let angle = Float(index) * 2 * .pi / Float(sides)
      let direction = SIMD3(cos(angle), 0, sin(angle))
      let low = direction * 0.49 + [0, shadeBottom, 0]
      let high = direction * 0.29 + [0, shadeBottom + 0.48, 0]
      let length = simd_distance(low, high)
      parts.append(
        part(
          box([0.035, length, 0.035]), pleat, at: centre + (low + high) / 2,
          turn: simd_quatf(from: [0, 1, 0], to: simd_normalize(high - low))))
    }
    return parts
  }

  // MARK: - Plants and soft things

  /// A terracotta pot with a lip and a full head of oval leaves on thin stems.
  func leafyPlant(_ piece: GenzPiece) -> [Entity] {
    let centre = GenzRoomPoint(0.6, 0.6, 0).scene
    let pot = piece.slot(0)
    let profile: [SIMD2<Float>] = [
      [0, 0], [0.24, 0], [0.27, 0.03], [0.32, 0.44], [0.36, 0.46], [0.37, 0.52], [0.35, 0.56],
      [0.32, 0.55], [0.31, 0.53], [0, 0.53],
    ]
    var parts: [Entity] = [
      part(lathe("leafy pot", profile, sides: 28), glaze(pot), at: centre),
      part(
        lathe("leafy soil", [[0.31, 0.53], [0.31, 0.54], [0, 0.54]], sides: 20),
        matte(GenzColour(0x3B2A20)), at: centre),
    ]
    let leaf = cached("leafy leaf soft") {
      var mesh = GenzSmooth()
      for side: Float in [1, -1] {
        mesh.grid(columns: 6, rows: 10, flip: side < 0) { u, v in
          let across = (u * 2 - 1) * 0.15 * sin(v * .pi) * (1 - 0.3 * v)
          let fold = abs(u * 2 - 1) * 0.04
          return [across, v * 0.7, fold + side * 0.008 * sin(v * .pi) + 0.06 * v * v]
        }
      }
      return mesh.mesh("leaf")
    }
    let colours = [
      matte(piece.slot(1)), matte(piece.slot(2)), matte(piece.slot(1).shaded(0.18)),
    ]
    let stem = matte(piece.slot(2).shaded(-0.1))
    let leaves: [(turn: Float, lean: Float, rise: Float, size: Float)] = [
      (0.1, 0.9, 0.2, 1), (0.9, 0.7, 0.35, 1.1), (1.7, 1.0, 0.15, 0.9), (2.5, 0.6, 0.45, 1.15),
      (3.3, 0.95, 0.25, 1), (4.1, 0.75, 0.4, 1.05), (4.9, 1.05, 0.1, 0.9), (5.7, 0.65, 0.3, 1.1),
      (0.5, 0.35, 0.7, 1.2), (2.1, 0.3, 0.75, 1.15), (3.8, 0.4, 0.65, 1.1), (5.3, 0.3, 0.8, 1.2),
    ]
    for (index, spec) in leaves.enumerated() {
      let base = centre + [0, 0.56 + spec.rise, 0]
      if spec.rise > 0.12 {
        parts.append(
          part(
            prism(sides: 4, radius: 0.012, top: 0.012, height: spec.rise), stem,
            at: centre + [0, 0.56, 0]))
      }
      let model = part(
        leaf, colours[index % colours.count], at: base,
        turn: simd_quatf(angle: spec.turn, axis: [0, 1, 0])
          * simd_quatf(angle: spec.lean, axis: [1, 0, 0]))
      model.scale = .one * spec.size
      parts.append(model)
    }
    return parts
  }

  /// A round rug in rings, with a ring of dots and a star of squares at its heart.
  func patternRug(_ piece: GenzPiece) -> [Entity] {
    let centre = GenzRoomPoint(1.4, 1.4, 0).scene
    var parts: [Entity] = []
    // Each ring, dot and the fringe stands clear of what is under it, so no two share a plane.
    let rings: [(radius: Float, height: Float, slot: Int)] = [
      (1.4, 0.02, 0), (1.18, 0.03, 1), (0.8, 0.04, 2), (0.45, 0.05, 1),
    ]
    for ring in rings {
      let edge = ring.radius
      let profile: [SIMD2<Float>] = [
        [edge, 0], [edge, ring.height - 0.008], [edge - 0.02, ring.height], [0, ring.height],
      ]
      parts.append(
        part(
          lathe("rug ring \(ring.radius)", profile, sides: 48, repeats: 12),
          matte(piece.slot(ring.slot), .linen, repeats: [12, 1]), at: centre))
    }
    var dots: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for index in 0..<18 {
      let angle = Float(index) * 2 * .pi / 18
      dots.append((centre + [cos(angle) * 0.99, 0.04, sin(angle) * 0.99], [0.11, 0.012, 0.11]))
    }
    for index in 0..<8 {
      let angle = Float(index) * 2 * .pi / 8 + 0.2
      dots.append((centre + [cos(angle) * 0.62, 0.05, sin(angle) * 0.62], [0.1, 0.012, 0.1]))
    }
    parts.append(part(boxes("rug dots", dots), matte(piece.slot(0))))
    var fringe: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for index in 0..<40 {
      let angle = Float(index) * 2 * .pi / 40
      fringe.append(
        (centre + [cos(angle) * 1.45, 0.0025, sin(angle) * 1.45], [0.03, 0.005, 0.03]))
    }
    parts.append(part(boxes("rug fringe", fringe), matte(piece.slot(0).shaded(0.25))))
    return parts
  }

  /// A wooden chair with a jumper hung over its back and jeans folded on the seat.
  func chairWithClothes(_ piece: GenzPiece) -> [Entity] {
    let wood = matte(piece.slot(0))
    let jumper = matte(piece.slot(1))
    let jumperFold = matte(piece.slot(1).shaded(-0.15))
    var parts: [Entity] = []
    for x: Float in [0.05, 0.93] {
      for y: Float in [0.05, 0.88] { parts.append(block(x, y, 0, 0.08, 0.08, 0.82, wood)) }
      parts.append(block(x, 0.05, 0.82, 0.08, 0.08, 1.05, wood))
    }
    parts.append(pad(0, 0, 0.82, 1.06, 1.0, 0.1, radius: 0.03, wood))
    for z: Float in [1.25, 1.5] { parts.append(block(0.05, 0.06, z, 0.96, 0.05, 0.1, wood)) }
    parts.append(pad(0, 0.02, 1.8, 1.06, 0.12, 0.1, radius: 0.03, wood))
    parts.append(pad(0.06, -0.08, 1.82, 0.94, 0.28, 0.16, radius: 0.07, jumper))
    parts.append(pad(0.08, 0.14, 1.2, 0.9, 0.08, 0.64, radius: 0.035, jumper))
    parts.append(pad(0.3, 0.2, 1.24, 0.06, 0.04, 0.55, radius: 0.015, jumperFold))
    parts.append(pad(0.66, 0.2, 1.3, 0.06, 0.04, 0.48, radius: 0.015, jumperFold))
    parts.append(pad(0.1, -0.16, 1.35, 0.86, 0.08, 0.5, radius: 0.035, jumperFold))
    let sleeve = part(
      roundBox([0.16, 0.75, 0.14], radius: 0.06), jumper,
      at: GenzRoomPoint(1.06, 0.22, 1.5).scene, turn: simd_quatf(angle: 0.18, axis: [0, 0, 1]))
    parts.append(sleeve)
    let jeans = matte(piece.slot(2))
    parts.append(pad(0.15, 0.3, 0.92, 0.7, 0.55, 0.1, radius: 0.04, jeans))
    parts.append(
      pad(0.15, 0.3, 1.02, 0.7, 0.5, 0.06, radius: 0.025, matte(piece.slot(2).shaded(0.12))))
    return parts
  }

  /// Two mugs, one still full.
  func mugs(_ piece: GenzPiece) -> [Entity] {
    var parts: [Entity] = []
    let mugs: [(x: Float, slot: Int, full: Bool)] = [(0.13, 0, true), (0.42, 1, false)]
    let profile: [SIMD2<Float>] = [
      [0, 0], [0.085, 0], [0.095, 0.012], [0.1, 0.1], [0.1, 0.19], [0.096, 0.2], [0.088, 0.19],
      [0.086, 0.03], [0, 0.03],
    ]
    let handle = (0...8).map { step -> SIMD3<Float> in
      let angle = Float(step) / 8 * .pi - .pi / 2
      return [0.095 + cos(angle) * 0.055, 0.1 + sin(angle) * 0.055, 0]
    }
    for mug in mugs {
      let centre = GenzRoomPoint(mug.x, 0.15, 0).scene
      let body = glaze(piece.slot(mug.slot))
      parts.append(part(lathe("mug", profile, sides: 20), body, at: centre))
      parts.append(part(tube("mug handle", handle, radius: 0.016, sides: 6), body, at: centre))
      parts.append(
        part(
          lathe("mug drink", [[0.087, 0], [0, 0]], sides: 20),
          matte(mug.full ? GenzColour(0x4A2C1C) : piece.slot(mug.slot).shaded(-0.35)),
          at: centre + [0, mug.full ? 0.165 : 0.035, 0]))
    }
    return parts
  }

  // MARK: - Walls and music

  /// Polaroids taped to the wall at slight angles, each with a coloured print.
  func polaroids(_ piece: GenzPiece) -> [Entity] {
    let frame = matte(GenzColour(0xF4EFE6))
    let tape = matte(GenzColour(0xE8D9B8))
    let spots: [(x: Float, z: Float, tilt: Float)] = [
      (0.05, 0.55, 0.08), (0.45, 0.62, -0.06), (0.85, 0.52, 0.1), (1.24, 0.6, -0.05),
      (0.25, 0.04, -0.08), (0.66, 0.0, 0.05), (1.05, 0.07, -0.1),
    ]
    return spots.enumerated().map { index, spot in
      let holder = Entity()
      holder.position = GenzRoomPoint(spot.x + 0.17, 0.02, spot.z + 0.21).scene
      holder.orientation = simd_quatf(angle: spot.tilt, axis: [0, 0, 1])
      holder.addChild(part(box([0.34, 0.42, 0.015]), frame))
      holder.addChild(
        part(box([0.28, 0.28, 0.006]), matte(piece.slot(index % 3)), at: [0, 0.04, 0.009]))
      holder.addChild(part(box([0.14, 0.05, 0.004]), tape, at: [0, 0.21, 0.011]))
      return holder
    }
  }

  /// A record player: a wooden plinth, a platter with a spinning record and a tonearm.
  func recordPlayer(_ piece: GenzPiece) -> [Entity] {
    let wood = matte(piece.slot(0))
    let metal = matte(piece.slot(2))
    let platter = GenzRoomPoint(0.42, 0.44, 0.14).scene
    let arm = GenzRoomPoint(0.9, 0.18, 0.14).scene
    let armEnd = GenzRoomPoint(0.62, 0.5, 0.21).scene
    var parts: [Entity] = [pad(0, 0, 0.02, 1.1, 0.85, 0.12, radius: 0.03, wood)]
    for x: Float in [0.06, 0.96] {
      for y: Float in [0.06, 0.71] { parts.append(block(x, y, 0, 0.08, 0.08, 0.03, metal)) }
    }
    parts += [
      part(prism(sides: 24, radius: 0.36, top: 0.36, height: 0.03, turn: 0), metal, at: platter),
      part(
        prism(sides: 24, radius: 0.34, top: 0.34, height: 0.016, turn: 0),
        matte(GenzColour(0x151215)), at: platter + [0, 0.03, 0]),
      part(
        prism(sides: 24, radius: 0.25, top: 0.25, height: 0.024, turn: 0),
        matte(GenzColour(0x27222A)), at: platter + [0, 0.03, 0]),
      part(
        prism(sides: 16, radius: 0.1, top: 0.1, height: 0.032, turn: 0), matte(piece.slot(1)),
        at: platter + [0, 0.03, 0]),
      part(prism(sides: 8, radius: 0.07, top: 0.06, height: 0.08), metal, at: arm),
      part(
        box([0.025, 0.025, simd_distance(arm, armEnd)]), metal,
        at: (arm + [0, 0.08, 0] + armEnd) / 2,
        turn: simd_quatf(from: [0, 0, 1], to: simd_normalize(armEnd - arm - [0, 0.08, 0]))),
      block(0.75, 0.66, 0.14, 0.2, 0.1, 0.03, metal),
    ]
    return parts
  }

  /// A bookshelf speaker: a wooden box with a dark grille, a woofer and a tweeter.
  func speaker(_ piece: GenzPiece) -> [Entity] {
    let facing = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
    let cone = matte(piece.slot(2))
    let rim = matte(piece.slot(2).shaded(0.2))
    return [
      pad(0, 0, 0, 0.6, 0.55, 1.0, radius: 0.03, matte(piece.slot(0))),
      block(0.05, 0.55, 0.05, 0.5, 0.01, 0.9, matte(piece.slot(1))),
      part(
        prism(sides: 16, radius: 0.19, top: 0.19, height: 0.02, turn: 0), rim,
        at: GenzRoomPoint(0.3, 0.56, 0.36).scene, turn: facing),
      part(
        prism(sides: 16, radius: 0.16, top: 0.06, height: 0.05, turn: 0), cone,
        at: GenzRoomPoint(0.3, 0.57, 0.36).scene, turn: facing),
      part(
        prism(sides: 12, radius: 0.08, top: 0.08, height: 0.02, turn: 0), rim,
        at: GenzRoomPoint(0.3, 0.56, 0.76).scene, turn: facing),
      part(sphere(0.045), cone, at: GenzRoomPoint(0.3, 0.57, 0.76).scene),
    ]
  }
}
