import CoreGraphics
import Foundation
import RealityKit

/// Where the furniture of one styled room and set was moved to, by piece.
struct GenzSpotStore {
  let defaults: UserDefaults
  let key: GenzLayout.Key

  private var storageKey: String { "genz.spots.\(key.style.rawValue).\(key.furniture.rawValue)" }

  func load() -> [String: NookiLayout.Spot] {
    defaults.data(forKey: storageKey)
      .flatMap { try? JSONDecoder().decode([String: NookiLayout.Spot].self, from: $0) } ?? [:]
  }

  func save(_ spots: [String: NookiLayout.Spot]) {
    if spots.isEmpty {
      defaults.removeObject(forKey: storageKey)
    } else {
      defaults.set(try? JSONEncoder().encode(spots), forKey: storageKey)
    }
  }
}

@MainActor
extension GenzRoom {
  /// Makes the furniture on the floor movable. What stands on a piece, such as a lamp on a
  /// table, rides on it. The piece the cat lives on and the table under the lamp stay where they
  /// are: the cat's walks and the lamp's glow are laid out around them.
  func arrangeDecor(_ holders: [Entity]) {
    let placements = layout.pieces
    let floorIndices = placements.indices.filter { placements[$0].centre.z == 0 }
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
    for (rider, base) in bases {
      holders[rider].setParent(holders[base], preservingWorldTransform: true)
    }
    let lampKinds: Set<GenzPiece.Kind> = [.sunsetLamp, .thriftLamp, .pleatedLamp]
    let lampTables = Set(
      bases.filter { lampKinds.contains(placements[$0.key].piece.kind) }.map(\.value))
    let catSpot = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
    let stored = spots.load()
    for index in floorIndices {
      let placement = placements[index]
      let name = Self.decorName(placement, index: index)
      let box = Self.box(of: placement)
      let carriesCat =
        layout.cat.spot.z > 0.1 && placement.piece.kind.size.z > layout.cat.spot.z * 0.5
        && box.contains(catSpot)
      if carriesCat || lampTables.contains(index) {
        decor.addFixed(name, box)
        continue
      }
      let size = placement.piece.kind.size
      let flat = Self.isFlat(placement.piece.kind)
      SceneParts.makeTappable(
        holders[index], size: [size.x, max(size.z, 0.2), size.y],
        center: [0, max(size.z, 0.2) / 2, 0])
      decor.register(name, holder: holders[index], half: box.half, isFlat: flat)
      if let spot = stored[name] {
        decor.place(name, at: DecorBox(centre: [spot.x, spot.z], half: box.half, yaw: spot.yaw))
      }
    }
    decor.buildMarker()
    room.addChild(decor.marker)
    decor.onMoved = { [weak self] name, piece, box in self?.remember(name, piece: piece, at: box) }
  }

  /// The floor point under `point` in the view, in the plan's terms.
  func floorPoint(under point: CGPoint) -> SIMD2<Float>? {
    NookiFloorRay.floorPoint(
      under: SIMD2(Float(point.x), Float(point.y)),
      viewSize: SIMD2(Float(viewSize.width), Float(viewSize.height)), camera: camera.position,
      target: camera.target, verticalFieldOfView: camera.fieldOfView)
  }

  /// Every piece back where the room first put it.
  func resetDecor() {
    _ = decor.resetAll()
    spots.save([:])
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
      box == piece.home ? nil : NookiLayout.Spot(x: box.centre.x, z: box.centre.y, yaw: box.yaw)
    spots.save(stored)
    pieceMoved(name)
  }

  static func decorName(_ placement: GenzLayout.Placement, index: Int) -> String {
    "\(placement.piece.kind.rawValue)-\(index)"
  }

  static func isFlat(_ kind: GenzPiece.Kind) -> Bool {
    [.patternRug, .roundRug, .checkeredRug].contains(kind)
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
