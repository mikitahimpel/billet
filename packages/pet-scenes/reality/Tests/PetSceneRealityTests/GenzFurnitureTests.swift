import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzFurnitureTests {
  /// The first pieces, made of plain blocks, which the furnished sets replace.
  nonisolated private static let plain: Set<GenzPiece.Kind> = [
    .platformBed, .cubeNightstand, .checkeredRug, .hoodiePile, .daybed, .milkCrate, .thriftLamp,
    .roundRug,
  ]

  @Test(arguments: [RoomStyle.sunsetLamp, .windowSeat])
  func theFirstSetLeavesTheRoomAsItWas(_ style: RoomStyle) throws {
    let first = try #require(GenzLayout.of(style))
    let original = try #require(GenzLayout.of(style, furniture: .original))
    #expect(first.pieces.map(\.piece) == original.pieces.map(\.piece))
    #expect(original.furniture == .original)
  }

  @Test(arguments: [RoomStyle.sunsetLamp, .windowSeat], [RoomFurniture.cosyNook, .retroDen])
  func aFurnishedSetHasNoPlainPieces(_ style: RoomStyle, _ furniture: RoomFurniture) throws {
    let layout = try #require(GenzLayout.of(style, furniture: furniture))
    let kinds = Set(layout.pieces.map(\.piece.kind))
    #expect(kinds.isDisjoint(with: Self.plain))
    #expect(kinds.contains(.polaroids) && kinds.contains(.mugs))
    #expect(kinds.intersection([.quiltedBed, .quiltedDaybed, .windowBench]).count == 1)
    #expect(layout.furniture == furniture)
  }

  @Test(arguments: [RoomStyle.sunsetLamp, .windowSeat])
  func theTwoSetsDiffer(_ style: RoomStyle) throws {
    let cosy = try #require(GenzLayout.of(style, furniture: .cosyNook))
    let retro = try #require(GenzLayout.of(style, furniture: .retroDen))
    #expect(cosy.pieces.map(\.piece) != retro.pieces.map(\.piece))
    #expect(retro.pieces.contains { $0.piece.kind == .recordPlayer })
    #expect(retro.pieces.contains { $0.piece.kind == .speaker })
    #expect(cosy.key != retro.key)
  }

  @Test(arguments: [RoomStyle.sunsetLamp, .windowSeat], RoomFurniture.allCases)
  func everySetHasALampAndTheCatKeepsItsPlace(
    _ style: RoomStyle, _ furniture: RoomFurniture
  ) throws {
    let layout = try #require(GenzLayout.of(style, furniture: furniture))
    let lamps: Set<GenzPiece.Kind> = [.sunsetLamp, .thriftLamp, .pleatedLamp]
    #expect(layout.pieces.contains { lamps.contains($0.piece.kind) })
    let first = try #require(GenzLayout.of(style))
    #expect(layout.cat.spot == first.cat.spot)
    #expect((layout.catSurface == nil) == (first.catSurface == nil))
  }

  @Test func eachRoomAndSetIsItsOwnRoomInTheCache() throws {
    let rooms = GenzRoomCache()
    let cosy = try #require(GenzLayout.of(.windowSeat, furniture: .cosyNook))
    let retro = try #require(GenzLayout.of(.windowSeat, furniture: .retroDen))
    #expect(rooms.room(cosy) !== rooms.room(retro))
    #expect(rooms.room(cosy) === rooms.room(cosy))
  }

  @Test func thePleatedLampHasABulbForTheLightAndAGlassThatStaysLit() {
    let lamp = GenzKit().build(GenzPiece(.pleatedLamp))
    #expect(lamp.findEntity(named: GenzRoom.bulbName) != nil)
    #expect(lamp.findEntity(named: GenzRoom.bulbGlassName) != nil)
  }

  // MARK: - Window Seat

  nonisolated private static let seatSets: [RoomFurniture] = [.cosyNook, .retroDen]

  /// The seat's cushion is level with the sill, where the cat sits and walks.
  @Test(arguments: seatSets)
  func theSeatIsWhereTheCatSits(_ furniture: RoomFurniture) throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: furniture))
    let seat = try #require(layout.pieces.first { $0.piece.kind == .windowBench })
    #expect(GenzPiece.Kind.windowBench.size.z == layout.cat.spot.z)
    let surface = try #require(layout.catSurface)
    #expect(surface.min.x <= seat.centre.x - 3, "the seat is the cat's surface")
  }

  /// What stands on the floor never overlaps, rugs aside, and nothing pokes out of the room.
  @Test(arguments: seatSets)
  func piecesKeepToTheirOwnPlaces(_ furniture: RoomFurniture) throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: furniture))
    let flat: Set<GenzPiece.Kind> = [.patternRug]
    let standing = layout.pieces.filter { $0.centre.z == 0 && !flat.contains($0.piece.kind) }
    let boxes = standing.map { Self.footprint($0) }
    for (index, box) in boxes.enumerated() {
      #expect(
        box.min.x >= -0.001 && box.min.y >= -0.001, "\(standing[index].piece.kind) is in the wall")
      #expect(box.max.x <= 7.6 && box.max.y <= 6, "\(standing[index].piece.kind) is off the floor")
      for other in boxes.indices where other > index {
        let touch: Float = 0.001
        let apart =
          box.max.x <= boxes[other].min.x + touch || boxes[other].max.x <= box.min.x + touch
          || box.max.y <= boxes[other].min.y + touch || boxes[other].max.y <= box.min.y + touch
        #expect(apart, "\(standing[index].piece.kind) overlaps \(standing[other].piece.kind)")
      }
    }
  }

  /// The footprint of a piece turned by a quarter or not at all, as its upright rectangle.
  private static func footprint(_ placement: GenzLayout.Placement) -> (
    min: SIMD2<Float>, max: SIMD2<Float>
  ) {
    let size = placement.piece.kind.size
    let turned = abs(sin(placement.yaw)) > 0.7
    let half = SIMD2(turned ? size.y : size.x, turned ? size.x : size.y) / 2
    let centre = SIMD2(placement.centre.x, placement.centre.y)
    return (centre - half, centre + half)
  }

  /// The furnished room stays light enough to draw every frame on an older phone.
  @Test(arguments: seatSets)
  func theFurnitureKeepsToItsTriangleBudget(_ furniture: RoomFurniture) throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: furniture))
    let kit = GenzKit()
    var triangles = 0
    for placement in layout.pieces {
      SceneParts.visit(kit.build(placement.piece)) { entity in
        guard let mesh = (entity as? ModelEntity)?.model?.mesh else { return }
        for model in mesh.contents.models {
          for part in model.parts { triangles += (part.triangleIndices?.count ?? 0) / 3 }
        }
      }
    }
    #expect(triangles < 120_000, "\(triangles) triangles")
    #expect(triangles > 20_000, "\(triangles) triangles")
  }

  @Test func everyCandleIsLit() {
    let candles = GenzKit().build(GenzPiece(.candles))
    var flames = 0
    SceneParts.visit(candles) { if $0.name == GenzRoom.flameName { flames += 1 } }
    #expect(flames == 3)
  }
}
