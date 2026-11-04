import CoreGraphics
import Foundation
import OSLog
import Pet
import RealityKit

/// Where the furniture of one set was moved to in the room, by piece.
struct GenzSpotStore {
  let defaults: UserDefaults
  let key: GenzLayout.Key

  /// The name both partners' rooms know this room and furniture set by.
  var room: String { Self.room(key) }

  static func room(_ key: GenzLayout.Key) -> String {
    switch key.room {
    case .windowSeat: "windowSeat.\(key.furniture.rawValue)\(key.idolProps ? ".idol" : "")"
    case .nookiCabin: "nookiCabin"
    }
  }

  private var storageKey: String { "genz.spots.\(room)" }

  func load() -> [String: NookiSpot] {
    defaults.data(forKey: storageKey)
      .flatMap { try? JSONDecoder().decode([String: NookiSpot].self, from: $0) } ?? [:]
  }

  func save(_ spots: [String: NookiSpot]) {
    if spots.isEmpty {
      defaults.removeObject(forKey: storageKey)
    } else {
      defaults.set(try? JSONEncoder().encode(spots), forKey: storageKey)
    }
  }
}

@MainActor
extension GenzRoom {
  /// Makes the room's furniture movable, each piece on its own surface:
  /// - on the floor, everything standing there but the piece the cat lives on, whose walks are
  ///   laid out on its top;
  /// - on that piece's top, the seat, what lies on it: pillows, the throw, mugs, the cardigan;
  /// - on another piece's top, what stands on it, such as the lamp and candles on the side table
  ///   or the record player on its crate. They ride with it when it moves.
  func arrangeDecor(_ holders: [Entity]) {
    let placements = layout.pieces
    let floorIndices = placements.indices.filter { placements[$0].centre.z == 0 }
    let catSpot = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
    let seat = floorIndices.first { index in
      let placement = placements[index]
      return layout.cat.spot.z > 0.1
        && placement.piece.kind.size.z > layout.cat.spot.z * 0.5
        && Self.box(of: placement).contains(catSpot)
    }
    var bases: [Int: Int] = [:]
    for index in placements.indices where placements[index].centre.z > 0 {
      let spot = SIMD2(placements[index].centre.x, placements[index].centre.y)
      let base = floorIndices.first { floor in
        let piece = placements[floor]
        guard !Self.isFlat(piece.piece.kind) else { return false }
        return Self.box(of: piece).contains(spot)
      }
      if let base { bases[index] = base }
    }
    // What lies on the seat stays in the room's space, as the seat never moves; what stands on
    // anything else rides on it.
    for (rider, base) in bases where base != seat {
      holders[rider].setParent(holders[base], preservingWorldTransform: true)
    }
    if let seat, let surface = layout.catSurface {
      decor.addSurface(
        Self.seatSurface,
        plan: DecorPlan(minimum: surface.min, maximum: surface.max, grid: 0.1),
        parent: nil, markerHeight: layout.cat.spot.z + 0.02)
      decor.addFixed(Self.decorName(placements[seat], index: seat), Self.box(of: placements[seat]))
      decor.blockers = { [weak self] surface in
        guard let self, surface == Self.seatSurface else { return [:] }
        return ["cat": self.catFootprint]
      }
    }
    // The light switch on the back wall, left of the window: nothing is pushed up against it.
    decor.addFixed(
      "light switch", DecorBox(centre: [0.27, 0.03], half: [0.17, 0.03]), on: DecorSession.floor)
    for base in Set(bases.values) where base != seat {
      let half = SIMD2(placements[base].piece.kind.size.x, placements[base].piece.kind.size.y) / 2
      let top = placements[base].piece.kind.size.z
      decor.addSurface(
        Self.topSurface(Self.decorName(placements[base], index: base)),
        plan: DecorPlan(minimum: -half, maximum: half, grid: 0.05), parent: holders[base],
        markerHeight: top + 0.02)
    }
    let stored = spots.load()
    for index in placements.indices where index != seat {
      let placement = placements[index]
      let surface: String
      if floorIndices.contains(index) {
        surface = DecorSession.floor
      } else if let base = bases[index] {
        surface =
          base == seat
          ? Self.seatSurface : Self.topSurface(Self.decorName(placements[base], index: base))
      } else {
        // Hung on a wall: not movable yet.
        continue
      }
      register(placement, index: index, holder: holders[index], on: surface, stored: stored)
    }
    decor.buildMarker()
    room.addChild(decor.marker)
    decor.onMoved = { [weak self] name, piece, box in self?.remember(name, piece: piece, at: box) }
  }

  private func register(
    _ placement: GenzLayout.Placement, index: Int, holder: Entity, on surface: String,
    stored: [String: NookiSpot]
  ) {
    let name = Self.decorName(placement, index: index)
    let kind = placement.piece.kind
    let size = kind.size
    SceneParts.makeTappable(
      holder, size: [size.x, max(size.z, 0.2), size.y], center: [0, max(size.z, 0.2) / 2, 0])
    let half = Self.footprint(of: kind)
    decor.register(
      name, holder: holder, half: half, isFlat: Self.isFlat(kind), surface: surface,
      slidesOnly: Self.slidesOnly(kind))
    if let spot = stored[name] {
      let box = DecorBox(centre: [spot.x, spot.z], half: half, yaw: spot.yaw)
      guard decor.canStand(name, at: box) else {
        Self.decorLog.error("Dropped a bad saved spot for \(name, privacy: .public)")
        return
      }
      decor.place(name, at: box)
      moveInLayout(name)
    }
  }

  static let seatSurface = "seat"
  private static let decorLog = Logger(subsystem: "com.mikitahimpel.billet", category: "Decor")

  static func topSurface(_ base: String) -> String { "top:\(base)" }

  /// Half the footprint the piece keeps others off, on its surface. Most keep off their whole
  /// size; a pillow only where it rests on the seat, as it leans back over the glass, and the
  /// cardigan only its body, as its sleeve lies flat.
  static func footprint(of kind: GenzPiece.Kind) -> SIMD2<Float> {
    let size = kind.size
    switch kind {
    case .pillowLarge, .pillowLinen, .pillowSquare, .pillowSmall:
      return [kind.pillow.width / 2 - 0.01, 0.25]
    case .cardigan: return [size.x / 2, 0.3]
    default: return [size.x / 2, size.y / 2]
    }
  }

  /// Whether the piece only slides along the seat, keeping its depth and how it faces: a pillow
  /// leaning on the backrest, or a throw hanging over the front edge. The camera looks across the
  /// room at an angle, so a sideways drag on screen would otherwise push them off the seat.
  static func slidesOnly(_ kind: GenzPiece.Kind) -> Bool {
    kind.isPillow || kind == .blanket || kind == .cardigan
  }

  /// Where the cat's body lies now, as a footprint on the floor plane, round whichever way it
  /// faces.
  var catFootprint: DecorBox {
    let reach = layout.cat.length * 0.45
    return DecorBox(centre: [catHolder.position.x, catHolder.position.z], half: [reach, reach])
  }

  /// Keeps the layout's record of a piece in the room's space, on the floor or the seat, where
  /// decorating has it, so the cat's walks go round it there.
  func moveInLayout(_ name: String) {
    let surface = decor.surface(of: name)
    guard surface == DecorSession.floor || surface == Self.seatSurface,
      let dash = name.lastIndex(of: "-"), let index = Int(name[name.index(after: dash)...]),
      layout.pieces.indices.contains(index),
      let box = decor.plan(of: name)?.pieces[name]
    else { return }
    layout.pieces[index].centre.x = box.centre.x
    layout.pieces[index].centre.y = box.centre.y
    layout.pieces[index].yaw = box.yaw
  }

  /// The floor point under `point` in the view, in the plan's terms.
  func floorPoint(under point: CGPoint) -> SIMD2<Float>? {
    NookiFloorRay.floorPoint(
      under: SIMD2(Float(point.x), Float(point.y)),
      viewSize: SIMD2(Float(viewSize.width), Float(viewSize.height)), camera: camera.position,
      target: camera.target, verticalFieldOfView: camera.fieldOfView)
  }

  /// The point under `point` in the view on the surface the piece `name` stands on, in that
  /// surface's plan: the floor's, or the plane the piece rests on in its parent's space.
  func surfacePoint(under point: CGPoint, for name: String) -> SIMD2<Float>? {
    guard let rest = decor.rest(of: name), let parent = rest.holder.parent,
      decor.surface(of: name) != DecorSession.floor
    else { return floorPoint(under: point) }
    let height = parent.convert(position: [0, rest.height, 0], to: room).y
    guard
      let hit = NookiFloorRay.floorPoint(
        under: SIMD2(Float(point.x), Float(point.y)),
        viewSize: SIMD2(Float(viewSize.width), Float(viewSize.height)),
        camera: camera.position, target: camera.target, verticalFieldOfView: camera.fieldOfView,
        height: height)
    else { return nil }
    let local = parent.convert(position: [hit.x, height, hit.y], from: room)
    return SIMD2(local.x, local.z)
  }

  /// Where the lamp's bulb is now, carried wherever its table was moved.
  var lampPoint: GenzRoomPoint {
    guard let lampBulb else { return layout.lamp.at }
    let at = lampBulb.position(relativeTo: room)
    return GenzRoomPoint(at.x, at.z, at.y)
  }

  /// Every piece back where the room first put it.
  func resetDecor() {
    isRearranging = true
    _ = decor.resetAll()
    isRearranging = false
    spots.save([:])
    onArranged?(arrangement)
  }

  /// Where this room's furniture stands, as both partners' rooms share it.
  var arrangement: RoomArrangement {
    RoomArrangement(
      room: spots.room,
      spots: spots.load().mapValues {
        PieceSpot(x: Double($0.x), z: Double($0.z), yaw: Double($0.yaw))
      })
  }

  /// Stands the furniture where the partner arranged it: each piece named in `arranged` where it
  /// says, every other piece where the room first put it. A piece picked up here stays in hand.
  func arrange(_ arranged: [String: PieceSpot]) {
    let given = arranged.mapValues { NookiSpot(x: Float($0.x), z: Float($0.z), yaw: Float($0.yaw)) }
    guard !decor.pieces.isEmpty else {
      // Not built yet: the room stands its pieces from what is saved when it is.
      spots.save(given)
      return
    }
    let current = spots.load()
    var kept: [String: NookiSpot] = [:]
    isRearranging = true
    defer { isRearranging = false }
    for (name, piece) in decor.pieces where piece.placement == nil {
      guard name != decor.selected, let box = decor.plan(of: name)?.pieces[name] else {
        if let spot = current[name] { kept[name] = spot }
        continue
      }
      var target = piece.home
      if let spot = given[name] {
        let spotBox = DecorBox(centre: [spot.x, spot.z], half: box.half, yaw: spot.yaw)
        if decor.canStand(name, at: spotBox) {
          target = spotBox
          kept[name] = spot
        } else {
          Self.decorLog.error("Dropped a bad arranged spot for \(name, privacy: .public)")
        }
      }
      guard target != box else { continue }
      decor.place(name, at: target)
      moveInLayout(name)
      pieceMoved(name)
    }
    spots.save(kept)
  }

  func stepDecor(_ delta: Float) {
    guard decor.isMoving else { return }
    decor.step(delta, reduceMotion: reduceMotion)
    glow?.groundShadows()
    if let lampBulb { lampLight.position = lampBulb.position(relativeTo: room) }
  }

  private func remember(_ name: String, piece: DecorSession.Piece, at box: DecorBox) {
    var stored = spots.load()
    stored[name] =
      box == piece.home ? nil : NookiSpot(x: box.centre.x, z: box.centre.y, yaw: box.yaw)
    spots.save(stored)
    moveInLayout(name)
    pieceMoved(name)
    if !isRearranging { onArranged?(arrangement) }
  }

  static func decorName(_ placement: GenzLayout.Placement, index: Int) -> String {
    "\(placement.piece.kind.rawValue)-\(index)"
  }

  /// What a piece named by ``decorName(_:index:)`` is called, or `nil` for any other name.
  nonisolated static func title(ofDecorName name: String) -> String? {
    guard let dash = name.lastIndex(of: "-") else { return nil }
    return GenzPiece.Kind(rawValue: String(name[..<dash]))?.title
  }

  static func isFlat(_ kind: GenzPiece.Kind) -> Bool {
    [.patternRug, .roundRug].contains(kind)
  }

  /// The piece's footprint on the floor, turned with it.
  static func box(of placement: GenzLayout.Placement) -> DecorBox {
    let size = placement.piece.kind.size
    return DecorBox(
      centre: [placement.centre.x, placement.centre.y], half: [size.x / 2, size.y / 2],
      yaw: placement.yaw)
  }
}

extension DecorBox {
  /// Whether `point` lies on the footprint.
  func contains(_ point: SIMD2<Float>) -> Bool {
    let axes = Self.axes(yaw)
    let offset = point - centre
    return abs(simd_dot(offset, axes.0)) <= half.x && abs(simd_dot(offset, axes.1)) <= half.y
  }
}
