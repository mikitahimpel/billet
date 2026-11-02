import Foundation
import Pet
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
    #expect(
      kinds.contains(.polaroids) && kinds.contains(.mugs)
        && kinds.contains(.quiltedBed) != kinds.contains(.quiltedDaybed))
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
}
