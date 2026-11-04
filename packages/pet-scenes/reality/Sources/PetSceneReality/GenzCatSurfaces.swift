import Pet
import simd

/// One flat place the cat can be on: the floor, the top it lives on, or the top of a piece it
/// can get up onto, such as the side table, the pouf or the cat bed. Footprints are on the floor
/// plane (scene x and z); heights are scene heights.
struct GenzCatLevel: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case floor, seat, table, bed, top
  }

  /// Which one: ``floorID``, ``homeID`` for the top the cat lives on, else the index of its
  /// piece in the layout.
  var id: Int
  var kind: Kind
  var box: DecorBox
  /// How high its top is before the room is built and its pieces' surfaces are measured.
  var top: Float

  static let floorID = -1
  static let homeID = -2
}

/// A move from one level to the next: a jump (or a hop into a low bed) from a spot on one to a
/// spot on the other.
struct GenzCatJump: Equatable, Sendable {
  var from: SIMD2<Float>
  var to: SIMD2<Float>
  var fromLevel: Int
  var toLevel: Int
  /// The rise, negative for a jump down, in scene units.
  var rise: Float
}

/// The way from where the cat is to where it is going: walks on a level, and jumps between.
enum GenzCatWay: Equatable, Sendable {
  case walk(to: SIMD2<Float>, level: Int)
  case jump(GenzCatJump)
}

extension GenzPiece.Kind {
  /// What kind of level the cat can get up onto this piece's top as, or nil for one it can't.
  /// The piece the cat lives on is a level of its own (``GenzLayout/catLevels``).
  var catLevel: GenzCatLevel.Kind? {
    switch self {
    case .windowBench, .daybed, .quiltedDaybed: .seat
    case .sideTable, .milkCrate, .bookCrate, .knitPouf: .table
    case .catBed: .bed
    case .idolCatBed: .bed
    case .idolBeanBag, .idolBeanBagSage, .idolBeanBagTerracotta, .idolArmchair,
      .idolFloorCushionSage, .idolFloorCushionTerracotta, .idolCatTree:
      .top
    case .phoneOnCharger, .bookStack, .thriftLamp, .roundRug, .snakePlant, .pleatedLamp,
      .leafyPlant, .patternRug, .mugs, .polaroids, .recordPlayer, .speaker, .bookshelf,
      .wallShelves, .stringLights, .cardigan, .candles, .pillowLarge, .pillowLinen, .pillowSquare,
      .pillowSmall, .blanket, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolDesk, .idolFrameLandscape,
      .idolPosterMoon, .idolClock, .idolFishTank, .idolScratchPost, .idolFiddleFig, .idolPothos,
      .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolYarnBasket:
      nil
    }
  }

  /// Whether the cat walks over it where it lies, as over a rug, a phone or the cardigan, its
  /// feet on top of it, rather than going round it.
  var catWalksOver: Bool {
    switch self {
    case .roundRug, .patternRug, .idolRug, .phoneOnCharger, .cardigan, .blanket, .idolThrow,
      .idolBooks:
      true
    default: false
    }
  }

  /// How high above its foot the cat stands on it before the piece's surface is measured: the
  /// top of its box for a plain block, less for one whose top is soft or dished.
  var catStandShare: Float {
    switch self {
    case .catBed: 0.4
    case .idolCatBed: 0.35
    case .idolBeanBag, .idolBeanBagSage, .idolBeanBagTerracotta: 0.85
    case .idolArmchair: 0.55
    case .daybed, .quiltedDaybed: 0.6
    default: 1
    }
  }
}

extension GenzLayout {
  /// How high the cat jumps up or down at most, in scene units (about a metre).
  static let catJumpHeight: Float = 2.4
  /// How far across a gap the cat jumps, in shares of its length.
  static let catJumpReach: Float = 1.7
  /// The most the ground may rise or fall under a walking cat before it hops instead, in scene
  /// units (about 5 cm): over a rug or the cardigan it walks, into the cat bed it hops.
  static let catStepHeight: Float = 0.12

  /// Every level the cat can be on: the floor, the top it lives on, and each piece standing on
  /// the floor (or on the top it lives on) that it can get up onto.
  var catLevels: [GenzCatLevel] {
    var out = [
      GenzCatLevel(
        id: GenzCatLevel.floorID, kind: .floor,
        box: DecorBox(centre: floor / 2, half: floor / 2), top: 0)
    ]
    let home = homeLevelPiece
    if let surface = catSurface {
      out.append(
        GenzCatLevel(
          id: GenzCatLevel.homeID, kind: .seat,
          box: DecorBox(
            centre: (surface.min + surface.max) / 2, half: (surface.max - surface.min) / 2),
          top: cat.spot.z))
    }
    for (index, placement) in pieces.enumerated() where index != home {
      guard let kind = placement.piece.kind.catLevel, placement.centre.z < 0.05 else { continue }
      let size = placement.piece.kind.size
      out.append(
        GenzCatLevel(
          id: index, kind: kind,
          box: DecorBox(
            centre: [placement.centre.x, placement.centre.y],
            half: [size.x / 2, size.y / 2] * (placement.piece.kind.idol?.footprint ?? 1),
            yaw: placement.yaw),
          top: placement.centre.z + size.z * placement.piece.kind.catStandShare))
    }
    return out
  }

  /// The index of the piece whose top the cat lives on, or nil when it lives on a top of its own
  /// (the sill) or on the floor.
  var homeLevelPiece: Int? {
    guard catTop == nil, cat.spot.z > 0.1 else { return nil }
    let spot = SIMD2(cat.spot.x, cat.spot.y)
    return pieces.firstIndex { placement in
      let size = placement.piece.kind.size
      let box = DecorBox(
        centre: [placement.centre.x, placement.centre.y], half: [size.x / 2, size.y / 2],
        yaw: placement.yaw)
      return box.distance(to: spot) == 0 && size.z > cat.spot.z * 0.5
    }
  }

  /// The level the cat lives on: its top, or the floor.
  var catHomeLevel: Int { catSurface == nil ? GenzCatLevel.floorID : GenzCatLevel.homeID }

  func catLevel(_ id: Int) -> GenzCatLevel? { catLevels.first { $0.id == id } }

  /// The level whose piece is `index`, or the cat's own top for the piece it lives on.
  func catLevel(ofPiece index: Int) -> Int? {
    if index == homeLevelPiece { return GenzCatLevel.homeID }
    return pieces.indices.contains(index) && pieces[index].piece.kind.catLevel != nil
      && pieces[index].centre.z < 0.05 ? index : nil
  }

  /// What the cat's body must keep off on `level`. On its own top, everything standing there and
  /// the pillows (``catObstacles``); on the floor, every piece standing on it but the flat ones it
  /// walks over, the levels it jumps onto among them; on another top, what stands on that top.
  func catObstacles(on level: Int) -> [GenzCatObstacle] {
    guard level != GenzCatLevel.homeID else { return catObstacles }
    guard let surface = catLevel(level) else { return [] }
    let home = homeLevelPiece
    var out: [GenzCatObstacle] = []
    for (index, placement) in pieces.enumerated() where index != level {
      let kind = placement.piece.kind
      let size = kind.size
      guard size.z >= 0.1, !kind.catWalksOver else { continue }
      let centre = SIMD2(placement.centre.x, placement.centre.y)
      let standsHere: Bool
      if level == GenzCatLevel.floorID {
        // On the floor (a lamp on the side table stands on the table, not here), or hung on a
        // wall low enough to be in the way.
        standsHere = placement.centre.z < 0.05 || index == home
      } else {
        standsHere =
          abs(placement.centre.z - surface.top) < 0.2 && surface.box.distance(to: centre) == 0
      }
      guard standsHere else { continue }
      let share = kind.idol?.footprint ?? 1
      out.append(
        GenzCatObstacle(
          box: DecorBox(
            centre: centre, half: [size.x / 2, size.y / 2] * share, yaw: placement.yaw),
          top: placement.centre.z + size.z))
    }
    if level == GenzCatLevel.floorID, let catTop {
      // The sill the cat lives on in the first room reaches over the daybed under it.
      out.append(
        GenzCatObstacle(
          box: DecorBox(centre: (catTop.min + catTop.max) / 2, half: (catTop.max - catTop.min) / 2),
          top: cat.spot.z))
    }
    return out
  }

  /// The part of `level` the middle of the cat's body may be on: in from its edges by `margin`,
  /// and for the floor in from the walls.
  func catArea(of level: GenzCatLevel, margin: Float) -> DecorBox {
    DecorBox(
      centre: level.box.centre, half: simd_max(level.box.half - margin, .zero), yaw: level.box.yaw)
  }

  /// Whether the cat's body fits at `point` on `level`, facing `heading`, its middle at least
  /// `margin` in from the edges.
  func catFits(
    at point: SIMD2<Float>, heading: Float, on level: GenzCatLevel, obstacles: [GenzCatObstacle],
    shape: GenzCatShape, margin: Float
  ) -> Bool {
    guard catArea(of: level, margin: margin).distance(to: point) == 0 else { return false }
    return catBodyIsClear(
      at: point, heading: heading, ground: level.top, obstacles: obstacles, shape: shape,
      pad: GenzCatBody.pad)
  }

  /// The nearest spot to `point` on `level` the standing cat fits, facing any way, or nil.
  func catSpot(near point: SIMD2<Float>, on level: GenzCatLevel, obstacles: [GenzCatObstacle])
    -> SIMD2<Float>?
  {
    if level.id == GenzCatLevel.homeID { return onCatSurface(point) }
    let shape = catBody.standing
    let margin = level.kind == .floor ? cat.length * shape.radius : cat.length * 0.25
    let area = catArea(of: level, margin: margin)
    let axes = DecorBox.axes(area.yaw)
    let offset = point - area.centre
    let local = simd_clamp(
      SIMD2(simd_dot(offset, axes.0), simd_dot(offset, axes.1)), -area.half, area.half)
    let start = area.centre + axes.0 * local.x + axes.1 * local.y
    func fits(_ at: SIMD2<Float>) -> Bool {
      catArea(of: level, margin: margin).distance(to: at) == 0
        && (0..<6).contains { turn in
          catBodyIsClear(
            at: at, heading: Float(turn) * .pi / 6, ground: level.top, obstacles: obstacles,
            shape: shape, pad: GenzCatBody.pad)
        }
    }
    if fits(start) { return start }
    let step: Float = 0.1
    let rings = Int((simd_length(level.box.half) * 2 / step).rounded(.up))
    for ring in 1...max(rings, 1) {
      var best: SIMD2<Float>?
      for i in -ring...ring {
        for j in -ring...ring where abs(i) == ring || abs(j) == ring {
          let at = start + SIMD2(Float(i), Float(j)) * step
          guard best.map({ simd_distance(at, start) < simd_distance($0, start) }) ?? true,
            fits(at)
          else { continue }
          best = at
        }
      }
      if let best { return best }
    }
    return nil
  }

  /// The jump from `from` to `to`, if the cat can make one: tops near enough across and in
  /// height, a spot to leave from on the one and to land on on the other. It leaves from the
  /// edge of the first nearest the second, and lands just in from the edge of the second.
  func catJump(from: GenzCatLevel, to: GenzCatLevel) -> GenzCatJump? {
    let rise = to.top - from.top
    guard abs(rise) <= Self.catJumpHeight, abs(rise) > Self.catStepHeight * 0.5 else { return nil }
    let length = cat.length
    let fromObstacles = catObstacles(on: from.id)
    let toObstacles = catObstacles(on: to.id)
    // The higher of the two stands on the lower one: from it the cat leaves (or lands) beside it.
    let (high, low) = rise > 0 ? (to, from) : (from, to)
    let highArea = catArea(of: high, margin: length * 0.3)
    // Spots round the higher top's edge, a little out from it on the lower level and a little in
    // from it on the higher one, nearest the cat's way first.
    let axes = DecorBox.axes(high.box.yaw)
    var best: (jump: GenzCatJump, cost: Float)?
    // Facing the edge to jump, the cat's nose is just short of it.
    let side = length * (catBody.standing.front + 0.05)
    for (axis, extent) in [
      (axes.0, high.box.half.x), (-axes.0, high.box.half.x),
      (axes.1, high.box.half.y), (-axes.1, high.box.half.y),
    ] {
      let across = SIMD2(-axis.y, axis.x)
      let alongReach = axis == axes.0 || axis == -axes.0 ? high.box.half.y : high.box.half.x
      for share in stride(from: Float(-0.8), through: 0.8, by: 0.2) {
        let edge = high.box.centre + axis * extent + across * (alongReach * share)
        let lowSpot = edge + axis * side
        guard let onHigh = catSpotIn(highArea, near: edge - axis * length * 0.35) else { continue }
        guard
          low.kind == .floor || catArea(of: low, margin: length * 0.25).distance(to: lowSpot) == 0
        else { continue }
        guard
          catFits(
            at: lowSpot, heading: CatTrip.heading(from: lowSpot, to: onHigh), on: low,
            obstacles: low.id == from.id ? fromObstacles : toObstacles, shape: catBody.standing,
            margin: low.kind == .floor ? length * catBody.standing.radius : length * 0.25),
          // Up there it turns as it lands, so a heading it fits in will do.
          Self.turns.contains { turn in
            catBodyIsClear(
              at: onHigh, heading: turn, ground: high.top,
              obstacles: (high.id == from.id ? fromObstacles : toObstacles).filter { !$0.sitOnTop },
              shape: bodyShape(on: high.id), pad: GenzCatBody.pad)
          },
          simd_distance(lowSpot, onHigh) <= length * Self.catJumpReach
        else { continue }
        let jump =
          rise > 0
          ? GenzCatJump(from: lowSpot, to: onHigh, fromLevel: from.id, toLevel: to.id, rise: rise)
          : GenzCatJump(from: onHigh, to: lowSpot, fromLevel: from.id, toLevel: to.id, rise: rise)
        let cost = simd_distance(jump.from, from.box.centre) + simd_distance(jump.to, to.box.centre)
        if best.map({ cost < $0.cost }) ?? true { best = (jump, cost) }
      }
    }
    return best?.jump
  }

  /// The walking body checked on `level`: on the cat's own top, where it has always walked
  /// between the pillows (which slide aside for it), the slimmer capsule; elsewhere its own.
  func bodyShape(on level: Int) -> GenzCatShape? {
    level == GenzCatLevel.homeID ? nil : catBody.standing
  }

  private func catSpotIn(_ area: DecorBox, near point: SIMD2<Float>) -> SIMD2<Float>? {
    guard area.half.x > 0 || area.half.y > 0 else { return nil }
    let axes = DecorBox.axes(area.yaw)
    let offset = point - area.centre
    let local = simd_clamp(
      SIMD2(simd_dot(offset, axes.0), simd_dot(offset, axes.1)), -area.half, area.half)
    return area.centre + axes.0 * local.x + axes.1 * local.y
  }

  /// The way from `start` on level `from` to `goal` on level `to`: walks round what is in the way
  /// on each level and jumps between them, through as few levels as it can. A goal on a level the
  /// cat can't get to is replaced by the nearest it can on its own level. Empty when it is there.
  func catWay(from start: SIMD2<Float>, on from: Int, to goal: SIMD2<Float>, on to: Int)
    -> [GenzCatWay]
  {
    if from == to {
      return catRoute(from: start, to: goal, on: from).map { .walk(to: $0, level: from) }
    }
    let levels = catLevels
    guard levels.contains(where: { $0.id == from }), levels.contains(where: { $0.id == to }) else {
      return catRoute(from: start, to: goal, on: from).map { .walk(to: $0, level: from) }
    }
    // Fewest jumps first, then the shortest way: a search over the levels, each jump found
    // once.
    var jumps: [Int: [GenzCatJump]] = [:]
    func edges(_ id: Int) -> [GenzCatJump] {
      if let known = jumps[id] { return known }
      guard let level = levels.first(where: { $0.id == id }) else { return [] }
      let found = levels.filter { $0.id != id }.compactMap { catJump(from: level, to: $0) }
      jumps[id] = found
      return found
    }
    var best: [Int: (cost: Float, via: GenzCatJump?, at: SIMD2<Float>)] = [from: (0, nil, start)]
    var frontier = [from]
    while !frontier.isEmpty {
      frontier.sort { best[$0]!.cost < best[$1]!.cost }
      let current = frontier.removeFirst()
      guard current != to else { break }
      let here = best[current]!
      for jump in edges(current) {
        let cost =
          here.cost + simd_distance(here.at, jump.from) + cat.length * 3
          + simd_distance(jump.from, jump.to)
        guard cost < best[jump.toLevel]?.cost ?? .infinity else { continue }
        best[jump.toLevel] = (cost, jump, jump.to)
        if !frontier.contains(jump.toLevel) { frontier.append(jump.toLevel) }
      }
    }
    guard best[to] != nil else {
      return catRoute(from: start, to: start, on: from).map { .walk(to: $0, level: from) }
    }
    var chain: [GenzCatJump] = []
    var at = to
    while let jump = best[at]?.via {
      chain.insert(jump, at: 0)
      at = jump.fromLevel
    }
    var out: [GenzCatWay] = []
    var position = start
    var level = from
    for jump in chain {
      out += catRoute(from: position, to: jump.from, on: level).map { .walk(to: $0, level: level) }
      out.append(.jump(jump))
      position = jump.to
      level = jump.toLevel
    }
    out += catRoute(from: position, to: goal, on: level).map { .walk(to: $0, level: level) }
    return out
  }
}

extension GenzLayout {
  /// Where near `point` on `level` the cat can lie down, its resting body (wider than its
  /// standing one, ``catBody``) clear of what stands there, facing `heading` or any way that
  /// fits. The pillows on its own top are left out: they slide aside for it
  /// (``pillowNudges(clearOf:heading:)``). `point` itself when nowhere near does.
  func catRestSpot(near point: SIMD2<Float>, on level: Int, heading: Float) -> SIMD2<Float> {
    let obstacles = catObstacles(on: level).filter { !$0.builtIn && !$0.sitOnTop }
    guard !obstacles.isEmpty, let surface = catLevel(level) else { return point }
    let shape = catBody.resting
    let ground = level == GenzCatLevel.homeID ? cat.spot.z : surface.top
    func fits(_ at: SIMD2<Float>) -> Bool {
      ([heading] + Self.turns).contains { turn in
        catBodyIsClear(
          at: at, heading: turn, ground: ground, obstacles: obstacles, shape: shape,
          pad: GenzCatBody.pad)
      }
    }
    if fits(point) { return point }
    let margin = cat.length * 0.3
    let area = catArea(of: surface, margin: margin)
    let step: Float = 0.08
    for ring in 1...Int((cat.length * 1.5 / step).rounded(.up)) {
      var best: SIMD2<Float>?
      for i in -ring...ring {
        for j in -ring...ring where abs(i) == ring || abs(j) == ring {
          let at = point + SIMD2(Float(i), Float(j)) * step
          guard area.distance(to: at) == 0,
            best.map({ simd_distance(at, point) < simd_distance($0, point) }) ?? true,
            !catClutter.contains(where: { $0.contains(at) }) || level != GenzCatLevel.homeID,
            fits(at)
          else { continue }
          best = at
        }
      }
      if let best { return best }
    }
    return point
  }

  /// Whether the resting cat at `point`, facing `heading`, is in something that stands on
  /// `level` now, such as a piece just moved onto it (pillows aside, which slide away).
  func catIsCrowded(at point: SIMD2<Float>, heading: Float, on level: Int, resting: Bool) -> Bool {
    let obstacles = catObstacles(on: level).filter { !$0.builtIn && !$0.sitOnTop }
    let ground = level == GenzCatLevel.homeID ? cat.spot.z : catLevel(level)?.top ?? 0
    return !catBodyIsClear(
      at: point, heading: heading, ground: ground, obstacles: obstacles,
      shape: resting ? catBody.resting : catBody.standing)
  }
}
