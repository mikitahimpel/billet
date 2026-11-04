import Foundation
import Pet
import PetScene
import RealityKit
import Testing
import simd

@testable import PetSceneReality

/// The cat stands on what it is on: its paws (or its belly, lying down) on the surface, not
/// above it or in it, on every kind of surface, for every cat and clip.
@MainActor
@Suite(.serialized) struct GenzCatGroundTests {
  /// 3 mm, in scene units (2.2 to the metre).
  static let tolerance: Float = 0.003 * GenzRoomPoint.perMetre

  static func built(_ layout: GenzLayout) async throws -> GenzRoom {
    let room = GenzRoom(
      layout: layout, kit: GenzKit(), cats: GenzCatSource(),
      spots: GenzSpotStore(defaults: UserDefaults(suiteName: "ground-\(UUID())")!, key: layout.key))
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !(room.isBuilt && room.hasCat), Date.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(room.isBuilt && room.hasCat)
    return room
  }

  /// The highest point of `roots`' meshes straight under `point` (scene x and z), found by
  /// casting a ray down through every triangle: no grid, unlike the room's own measure.
  static func exactTop(of roots: [Entity], at point: SIMD2<Float>, in space: Entity) -> Float? {
    var best: Float?
    for root in roots {
      SceneParts.visit(root) { entity in
        guard entity.isEnabled, let model = entity as? ModelEntity, let mesh = model.model?.mesh
        else { return }
        let transform = model.transformMatrix(relativeTo: space)
        for instance in mesh.contents.instances {
          guard let source = mesh.contents.models[instance.model] else { continue }
          let placed = transform * instance.transform
          for part in source.parts {
            guard let indices = part.triangleIndices?.elements else { continue }
            let points = part.positions.elements.map { p in
              let moved = placed * SIMD4(p, 1)
              return SIMD3(moved.x, moved.y, moved.z)
            }
            for i in stride(from: 0, to: indices.count - 2, by: 3) {
              let a = points[Int(indices[i])]
              let b = points[Int(indices[i + 1])]
              let c = points[Int(indices[i + 2])]
              guard let y = Self.down(through: point, a, b, c) else { continue }
              if y > best ?? -.infinity { best = y }
            }
          }
        }
      }
    }
    return best
  }

  /// Where a vertical line at `point` meets the triangle, if it does.
  private static func down(
    through point: SIMD2<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>
  ) -> Float? {
    let area = (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
    guard abs(area) > 1e-9 else { return nil }
    let u = ((b.x - point.x) * (c.z - point.y) - (c.x - point.x) * (b.z - point.y)) / area
    let v = ((c.x - point.x) * (a.z - point.y) - (a.x - point.x) * (c.z - point.y)) / area
    let w = 1 - u - v
    guard u >= 0, v >= 0, w >= 0 else { return nil }
    return a.y * u + b.y * v + c.y * w
  }

  /// The surfaces to stand a cat on in `room`: the floor, the seat it lives on, a rug, the cat
  /// bed, and the top of a table, each with a spot on it and what it is built from.
  static func surfaces(in room: GenzRoom) -> [(
    name: String, level: Int, spot: SIMD2<Float>, roots: [Entity]
  )] {
    let layout = room.layout
    var out: [(String, Int, SIMD2<Float>, [Entity])] = []
    func holders(_ kinds: (GenzPiece.Kind) -> Bool) -> [Entity] {
      layout.pieces.indices.filter { kinds(layout.pieces[$0].piece.kind) }.map {
        room.pieceHolders[$0]
      }
    }
    let flat = holders { $0.catWalksOver }
    var shell = [Entity]()
    if let found = room.room.findEntity(named: GenzRoom.shellName) { shell.append(found) }
    if let styler = room.styler { shell.append(styler.root) }
    let floor = layout.catLevel(GenzCatLevel.floorID)!
    if let open = layout.catSpot(
      near: [6.5, 5.3], on: floor, obstacles: layout.catObstacles(on: floor.id))
    {
      out.append(("floor", floor.id, open, shell + flat))
    }
    let home = layout.catHomeLevel
    let seat = layout.onCatSurface(SIMD2(layout.cat.spot.x, layout.cat.spot.y))
    let homeRoots = layout.homeLevelPiece.map { [room.pieceHolders[$0]] } ?? shell
    out.append(("seat", home, seat, homeRoots + flat))
    if let rug = layout.pieces.firstIndex(where: {
      $0.piece.kind == .patternRug || $0.piece.kind == .roundRug
    }) {
      let centre = SIMD2(layout.pieces[rug].centre.x, layout.pieces[rug].centre.y)
      if let spot = layout.catSpot(
        near: centre, on: floor, obstacles: layout.catObstacles(on: floor.id)),
        layout.pieces[rug].piece.kind.size.x / 2 > simd_distance(spot, centre)
      {
        out.append(("rug", floor.id, spot, shell + flat))
      }
    }
    for kind in [GenzPiece.Kind.catBed, .idolCatBed, .sideTable, .knitPouf] {
      guard let index = layout.pieces.firstIndex(where: { $0.piece.kind == kind }),
        let level = layout.catLevel(index)
      else { continue }
      let spot =
        layout.catSpot(near: level.box.centre, on: level, obstacles: layout.catObstacles(on: index))
        ?? level.box.centre
      out.append(("\(kind)", index, spot, [room.pieceHolders[index]] + flat))
    }
    if let cardigan = layout.pieces.firstIndex(where: { $0.piece.kind == .cardigan }) {
      let at = SIMD2(layout.pieces[cardigan].centre.x, layout.pieces[cardigan].centre.y)
      out.append(("cardigan", home, at, homeRoots + flat))
    }
    return out
  }

  /// The room's measure of every surface agrees with its meshes under the cat's paws.
  @Test(.timeLimit(.minutes(3))) func theRoomMeasuresEachSurfaceAsBuilt() async throws {
    for layout in [GenzLayout.of(.cosyNook), .of(.retroDen), .of(.cosyNook, idolProps: true)] {
      let room = try await Self.built(layout)
      let surfaces = Self.surfaces(in: room)
      var wanted: Set<String> = ["floor", "seat"]
      if !layout.idolProps { wanted.formUnion(["rug", "cardigan"]) }
      #expect(Set(surfaces.map(\.name)).isSuperset(of: wanted), "\(layout.key)")
      #expect(surfaces.contains { $0.name.lowercased().contains("catbed") }, "\(layout.key)")
      for surface in surfaces {
        let measured = room.groundHeight(at: surface.spot, on: surface.level)
        let exact = try #require(
          Self.exactTop(of: surface.roots, at: surface.spot, in: room.room),
          "\(layout.key) \(surface.name)")
        #expect(
          abs(measured - exact) < Self.tolerance,
          "\(layout.key) \(surface.name) at \(surface.spot): measured \(measured), built \(exact)")
      }
    }
  }

  /// Every clip of every cat has its lowest point measured, sample by sample over its length,
  /// and the rest pose the room loads is the one measured.
  @Test(.timeLimit(.minutes(3))) func everyCatsClipsAreMeasured() async throws {
    for model in CatModel.allCases {
      let table = try #require(CatGroundTable.of(model), "\(model)")
      let clips = CatCatalog.clips(model)
      #expect(!clips.isEmpty, "\(model)")
      for (action, range) in clips {
        let samples = try #require(table.clips[action.rawValue], "\(model) \(action)")
        let expected = range.duration * table.rate
        #expect(abs(Double(samples.count - 1) - expected) <= 1.5, "\(model) \(action)")
      }
      let cat = try #require(await NookiAssets.compiledCat(model), "\(model)")
      let bounds = cat.visualBounds(relativeTo: nil)
      let tall = bounds.extents.y / model.anatomy.length
      let rest = try #require(table.rest)
      #expect(abs(tall - rest) < 0.01, "\(model): loads \(tall) tall, measured \(rest)")
    }
  }

  /// Stood on each surface in each clip, the cat's lowest point is within 3 mm of the surface:
  /// the room's footing (its spring settled, the clip's own lift taken off) against the clip's
  /// measured lowest point and the surface's mesh. Every cat, every clip, a few times in each.
  @Test(.timeLimit(.minutes(8))) func theCatsLowestPointTouchesTheSurface() async throws {
    let room = try await Self.built(.of(.cosyNook))
    let surfaces = Self.surfaces(in: room)
    // Standing, its paws are under its shoulders and hips as well as its middle; it stands on
    // the highest of them. The surfaces as built there, standing and not.
    var exacts: [[Bool: Float]] = []
    for surface in surfaces {
      room.footing.level = surface.level
      var both: [Bool: Float] = [:]
      for standing in [true, false] {
        let paws = room.pawPoints(at: surface.spot, heading: 0, base: standing ? .stand : .sit)
        both[standing] = try #require(
          paws.compactMap { Self.exactTop(of: surface.roots, at: $0, in: room.room) }.max())
      }
      exacts.append(both)
    }
    for model in CatModel.allCases {
      room.setCat(CatChoice(model: model))
      await room.catLoad?.value
      let rig = try #require(room.rig, "\(model)")
      let table = try #require(room.footing.table, "\(model)")
      let length = room.layout.cat.length
      for (action, info) in rig.info.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        await Task.yield()
        rig.play(action, blend: 0)
        room.footing.shown = nil
        room.footing.fade = nil
        for (surface, exact) in zip(surfaces, exacts) {
          room.footing.level = surface.level
          room.footing.height = nil
          room.catHolder.position = [surface.spot.x, 3, surface.spot.y]
          room.bodyHeading = 0
          let top = exact[info.base == .stand]!
          // A second to settle, then a few moments through the clip.
          let start = room.clock
          var checked = 0
          while room.clock - start < 1 + min(info.duration, 4) {
            room.clock += 1 / 60
            room.stepFooting(1 / 60, rate: 1)
            let into = room.clock - room.footing.shownStart
            guard room.clock - start > 1, Int(into * 3) > checked else { continue }
            checked = Int(into * 3)
            let entity = try #require(room.catModel)
            let restLowest = room.catHolder.position.y + entity.position.y - room.footing.base.y
            let lowest = restLowest + table.lift(action, at: into, loops: info.loops) * length
            #expect(
              abs(lowest - top) < Self.tolerance,
              "\(model) \(action) on \(surface.name): \(lowest) vs \(top)")
          }
        }
      }
    }
  }

  /// A step onto something higher eases up rather than popping.
  @Test func theFootingEasesUpASpring() {
    var spring = GenzSpring(value: 0)
    var heights: [Float] = []
    for _ in 0..<30 {
      spring.step(towards: 1, by: 1 / 60)
      heights.append(spring.value)
    }
    #expect(heights[0] < 0.1)
    #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(heights.last! < 1.0001 && heights.last! > 0.95)
  }
}
