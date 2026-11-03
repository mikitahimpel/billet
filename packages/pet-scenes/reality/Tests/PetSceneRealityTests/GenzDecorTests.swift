import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzDecorTests {
  private let suite = "genz-decor-\(UUID())"

  /// A room with its pieces stood where the room stands them, ready for decorating.
  private func room(_ furniture: RoomFurniture = .cosyNook) throws -> (GenzRoom, [Entity]) {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: furniture))
    let room = GenzRoomCache(suite: suite).room(layout)
    let kit = GenzKit()
    let holders = layout.pieces.map { placement -> Entity in
      let holder = Entity()
      holder.position = placement.centre.scene
      holder.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
      holder.addChild(kit.build(placement.piece))
      room.room.addChild(holder)
      return holder
    }
    room.arrangeDecor(holders)
    room.decor.isOn = true
    return (room, holders)
  }

  private func name(_ kind: GenzPiece.Kind, in room: GenzRoom) throws -> String {
    let index = try #require(room.layout.pieces.firstIndex { $0.piece.kind == kind })
    return GenzRoom.decorName(room.layout.pieces[index], index: index)
  }

  @Test func floorFurnitureMovesButTheCatsSeatAndTheLampsTableStay() throws {
    let (room, _) = try room()
    for kind: GenzPiece.Kind in [.bookshelf, .knitPouf, .catBed, .leafyPlant, .patternRug] {
      #expect(room.decor.pieces[try name(kind, in: room)] != nil, "\(kind) moves")
    }
    #expect(room.decor.plan.fixed[try name(.windowBench, in: room)] != nil)
    #expect(room.decor.plan.fixed[try name(.sideTable, in: room)] != nil)
    #expect(room.decor.plan.flat.contains(try name(.patternRug, in: room)))
  }

  @Test func whatStandsOnAPieceRidesOnIt() throws {
    let (room, holders) = try room(.retroDen)
    let pieces = room.layout.pieces
    let player = try #require(pieces.firstIndex { $0.piece.kind == .recordPlayer })
    let crate = try #require(pieces.firstIndex { $0.piece.kind == .bookCrate })
    #expect(holders[player].parent === holders[crate])
    let lamp = try #require(pieces.firstIndex { $0.piece.kind == .pleatedLamp })
    let table = try #require(pieces.firstIndex { $0.piece.kind == .sideTable })
    #expect(holders[lamp].parent === holders[table])
  }

  @Test func nothingCanStandOnTheSeat() throws {
    let (room, holders) = try room()
    let pouf = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .knitPouf })
    #expect(room.decor.select(holders[pouf]))
    room.decor.beginDrag(at: [3.0, 3.35])
    room.decor.drag(to: [3.5, 0.8])
    guard case .blocked = room.decor.candidate?.fit else {
      Issue.record("the seat should block the pouf")
      return
    }
  }

  @Test func aMovedPieceIsWhereTheRoomOpensNextTime() throws {
    let (room, holders) = try room()
    let pouf = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .knitPouf })
    room.decor.select(holders[pouf])
    room.decor.beginDrag(at: [3.0, 3.35])
    room.decor.drag(to: [3.0, 5.0])
    room.decor.endDrag()
    let name = try name(.knitPouf, in: room)
    #expect(room.spots.load()[name]?.z == 5)

    let (again, againHolders) = try self.room()
    #expect(again.decor.plan.pieces[name]?.centre == [3, 5])
    #expect(againHolders[pouf].position.z == 5)

    again.resetDecor()
    #expect(again.spots.load().isEmpty)
  }
}
