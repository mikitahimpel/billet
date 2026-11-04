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
    let layout = GenzLayout.of(furniture)
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

  @Test func everythingMovesButTheCatsSeat() throws {
    let (room, _) = try room()
    let floor: [GenzPiece.Kind] = [
      .bookshelf, .knitPouf, .catBed, .leafyPlant, .snakePlant, .patternRug, .sideTable,
    ]
    for kind in floor {
      #expect(room.decor.surface(of: try name(kind, in: room)) == DecorSession.floor, "\(kind)")
    }
    let seat: [GenzPiece.Kind] = [
      .pillowLarge, .pillowLinen, .pillowSquare, .pillowSmall, .blanket, .mugs, .cardigan,
      .phoneOnCharger,
    ]
    for kind in seat {
      #expect(room.decor.surface(of: try name(kind, in: room)) == GenzRoom.seatSurface, "\(kind)")
    }
    let table = GenzRoom.topSurface(try name(.sideTable, in: room))
    for kind: GenzPiece.Kind in [.pleatedLamp, .candles] {
      #expect(room.decor.surface(of: try name(kind, in: room)) == table, "\(kind)")
    }
    #expect(room.decor.pieces[try name(.windowBench, in: room)] == nil)
    #expect(room.decor.plan.fixed[try name(.windowBench, in: room)] != nil)
    #expect(room.decor.plan.flat.contains(try name(.patternRug, in: room)))
  }

  @Test func aPillowSlidesAlongTheSeatAndTheCatGoesRoundItThere() throws {
    let (room, holders) = try room()
    let pillow = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .pillowSmall })
    let name = try name(.pillowSmall, in: room)
    let start = try #require(room.decor.plan(of: name)?.pieces[name])
    #expect(room.decor.select(holders[pillow]))
    room.decor.beginDrag(at: start.centre)
    room.decor.drag(to: start.centre + [0.9, 0])
    room.decor.endDrag()
    let moved = try #require(room.decor.plan(of: name)?.pieces[name])
    #expect(moved.centre.x > start.centre.x + 0.5)
    #expect(abs(holders[pillow].position.y - 1.28) < 0.001, "it stays on the seat")
    #expect(abs(room.layout.pieces[pillow].centre.x - moved.centre.x) < 0.001)
    #expect(
      room.layout.catObstacles.contains { abs($0.box.centre.x - moved.centre.x) < 0.001 },
      "the cat's obstacles follow it")
  }

  /// The camera looks across the room at an angle, so a sideways drag on screen also moves the
  /// finger towards the window; the pillow still only slides along the backrest.
  @Test func theBigPillowSlidesLeftAlongTheBackrestTowardsTheThrow() throws {
    let (room, holders) = try room()
    let pillow = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .pillowLarge })
    let name = try name(.pillowLarge, in: room)
    let start = try #require(room.decor.plan(of: name)?.pieces[name])
    #expect(!room.decor.canTurn(name))
    room.decor.select(holders[pillow])
    room.decor.beginDrag(at: start.centre)
    room.decor.drag(to: start.centre - [0.6, 0.3])
    let candidate = try #require(room.decor.candidate)
    #expect(candidate.fit == .free, "\(candidate.fit) at \(candidate.box.centre)")
    #expect(candidate.box.centre.y == start.centre.y)
    #expect(candidate.box.centre.x < start.centre.x - 0.3)
  }

  @Test func theThrowOnlySlidesAlongTheSeatsEdge() throws {
    let (room, holders) = try room()
    let blanket = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .blanket })
    let name = try name(.blanket, in: room)
    let start = try #require(room.decor.plan(of: name)?.pieces[name])
    #expect(!room.decor.canTurn(name))
    room.decor.select(holders[blanket])
    room.decor.beginDrag(at: start.centre)
    room.decor.drag(to: start.centre + [0.6, -0.6])
    let candidate = try #require(room.decor.candidate)
    #expect(candidate.box.centre.y == start.centre.y)
    #expect(candidate.box.yaw == start.yaw)
  }

  @Test func theLampRidesOnItsTableAndItsLightFollows() throws {
    let (room, holders) = try room()
    let table = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .sideTable })
    let lamp = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .pleatedLamp })
    let before = holders[lamp].position(relativeTo: room.room)
    room.decor.select(holders[table])
    room.decor.beginDrag(at: [1.12, 2.4])
    room.decor.drag(to: [2.12, 2.9])
    room.decor.endDrag()
    for _ in 0..<60 { room.decor.step(1 / 30, reduceMotion: true) }
    let after = holders[lamp].position(relativeTo: room.room)
    #expect(simd_distance(after, before) > 0.9)
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

  @Test func aMoveAndAResetAreToldToThePartner() throws {
    let (room, holders) = try room()
    var told: [RoomArrangement] = []
    room.onArranged = { told.append($0) }
    let pouf = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .knitPouf })
    let name = try name(.knitPouf, in: room)
    room.decor.select(holders[pouf])
    room.decor.beginDrag(at: [3.0, 3.35])
    room.decor.drag(to: [3.0, 5.0])
    room.decor.endDrag()
    #expect(told.last?.room == "windowSeat.cosyNook")
    #expect(told.last?.spots[name] == PieceSpot(x: 3, z: 5, yaw: 0))
    room.resetDecor()
    #expect(told.count == 2, "a reset is told once")
    #expect(told.last?.spots.isEmpty == true)
  }

  @Test func thePartnersArrangementMovesThePiecesWithoutTellingItBack() throws {
    let (room, holders) = try room()
    var told: [RoomArrangement] = []
    room.onArranged = { told.append($0) }
    let pouf = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .knitPouf })
    let name = try name(.knitPouf, in: room)
    room.arrange([name: PieceSpot(x: 3, z: 5, yaw: 0)])
    #expect(holders[pouf].position.z == 5)
    #expect(room.spots.load()[name]?.z == 5)
    #expect(room.layout.pieces[pouf].centre.y == 5, "the cat's map follows")
    room.arrange([:])
    #expect(abs(holders[pouf].position.z - 3.35) < 0.001)
    #expect(room.spots.load().isEmpty)
    #expect(told.isEmpty)
  }

  @Test func anArrangementBeforeTheRoomIsBuiltWaitsForIt() throws {
    let layout = GenzLayout.of(.cosyNook)
    let room = GenzRoomCache(suite: suite).room(layout)
    room.arrange(["knitPouf-3": PieceSpot(x: 3, z: 5, yaw: 0)])
    #expect(room.spots.load()["knitPouf-3"]?.z == 5)
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
    #expect(again.decor.plan.pieces[name]?.centre == [3, 3.35])
  }
}
