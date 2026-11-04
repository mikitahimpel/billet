import Foundation
import Pet
import Testing
import simd

@testable import PetSceneReality

@MainActor
@Suite struct NookiCabinTests {
  private let cabin = GenzLayout.nookiCabin

  @Test(arguments: RoomFurniture.allCases)
  func theCabinKeepsItsOwnFurnitureWhateverSetIsChosen(_ furniture: RoomFurniture) {
    let layout = GenzLayout.of(furniture, idolProps: true, room: .nookiCabin)
    #expect(layout.key == cabin.key)
    #expect(layout.key != GenzLayout.of(furniture).key)
    #expect(GenzLayout.of(layout.key).room == .nookiCabin)
  }

  @Test func windowSeatHasAnOutsideAndTheCabinHasNone() {
    #expect(GenzLayout.of(.cosyNook).hasOutside)
    #expect(!cabin.hasOutside)
    #expect(cabin.led.isEmpty)
    #expect(cabin.fairyHooks.isEmpty)
  }

  @Test func theCabinsArrangementIsKeptApartFromWindowSeats() {
    #expect(GenzSpotStore.room(cabin.key) == "nookiCabin")
    #expect(GenzSpotStore.room(GenzLayout.of(.cosyNook).key) == "windowSeat.cosyNook")
  }

  @Test func everyPieceStandsOnTheFloorInsideTheWalls() {
    for placement in cabin.pieces {
      let size = placement.piece.kind.size
      let name = placement.piece.kind.rawValue
      #expect(abs(placement.centre.z) < 0.001, "\(name)")
      #expect(placement.centre.x - size.x / 2 >= -0.01, "\(name)")
      #expect(placement.centre.y - size.y / 2 >= -0.01, "\(name)")
      #expect(placement.centre.x + size.x / 2 <= cabin.floor.x + 0.3, "\(name)")
      #expect(placement.centre.y + size.y / 2 <= cabin.floor.y + 0.3, "\(name)")
    }
  }

  @Test func theCatLivesOnTheFloorWithItsHomeInTheBed() throws {
    let bed = try #require(cabin.pieces.first { $0.piece.kind == .cabinBed })
    let home = SIMD2(cabin.cat.spot.x, cabin.cat.spot.y)
    let half = bed.piece.kind.size.x / 2
    #expect(simd_distance(home, SIMD2(bed.centre.x, bed.centre.y)) < half * 0.5)
    #expect(cabin.cat.spot.z == 0)
    let surface = try #require(cabin.catSurface)
    #expect(home == simd_clamp(home, surface.min, surface.max))
    #expect(!cabin.catClutter.contains { $0.contains(home) })
  }

  @Test func theCatGoesRoundTheNightstandButIntoItsBed() throws {
    let kinds = cabin.catObstacles.compactMap { obstacle in
      cabin.pieces.first {
        SIMD2($0.centre.x, $0.centre.y) == obstacle.box.centre
      }?.piece.kind
    }
    #expect(kinds.contains(.cabinNightstand))
    #expect(kinds.contains(.cabinCatTree))
    #expect(!kinds.contains(.cabinBed))
    #expect(!kinds.contains(.cabinRug))
  }

  @Test func theNoteHangsOnTheBackWallUnderTheGarland() {
    let note = cabin.note
    #expect(note.yaw == 0)
    #expect(note.centre.y > 0.02)
    #expect(note.centre.y < 0.3)
    let top = note.centre.z + note.height / 2
    let garland = NookiCabin.garlandPoint(0.5).y - NookiCabin.plankTop
    #expect(top < garland * NookiCabin.scale)
    #expect(note.centre.z - note.height / 2 > 1)
  }

  @Test func theSwitchHangsBetweenTheGarlandAndTheShelf() {
    let plate = cabin.switchPlate
    let half = GenzLightSwitch.plateSize.x / 2
    let garlandEnd = NookiCabin.room(NookiCabin.garland.x1, 0, 0).x
    let shelfStart = NookiCabin.room(0.27 - 0.165, 0, 0).x
    #expect(plate.x - half > garlandEnd)
    #expect(plate.x + half < shelfStart)
    #expect(plate.y == 0)
  }

  @Test func theCabinBuildsWithItsOwnLightsAndNoStyle() async throws {
    let room = GenzRoomCache(suite: "nooki-cabin-\(UUID())").room(cabin)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    #expect(room.styler == nil)
    #expect(room.root.findEntity(named: GenzRoom.lampName) != nil)
    #expect(room.root.findEntity(named: GenzRoom.flameName) != nil)
    #expect(room.root.findEntity(named: GenzRoom.noteName) != nil)
    #expect(room.street == nil)
  }

  /// The backdrop dims with the lights but stays warm under every preset and switch position.
  @Test func theBackdropDimsButNeverGoesDark() {
    let looks = RoomLighting.allCases.map(LightingLook.of) + [LightingLook.cosy, .moonlight]
    for look in looks {
      let brightness = NookiCabinBackdrop.brightness(look.key.boost)
      #expect(brightness >= 0.7 && brightness <= 1)
    }
    #expect(
      NookiCabinBackdrop.brightness(LightingLook.moonlight.key.boost)
        < NookiCabinBackdrop.brightness(LightingLook.amberLantern.key.boost))
  }
}
