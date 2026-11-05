import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzShadowTests {
  private func builtRoom() async throws -> GenzRoom {
    let layout = GenzLayout.of(.cosyNook)
    let room = GenzRoomCache(suite: "genz-shadow-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    room.setLighting(.amberLantern)
    return room
  }

  @Test func noTwoFurnitureShadowsShareAPlaneAndAllLieUnderTheRugs() async throws {
    let glow = try #require(try await builtRoom().glow)
    let heights = glow.pieceShadows.map(\.height)
    #expect(heights.count > 3)
    #expect(Set(heights).count == heights.count)
    #expect(heights.allSatisfy { $0 > 0 && $0 < 0.02 })
  }

  @Test func aShadowFollowsItsPieceAndStaysOnTheFloorWhileItIsCarried() async throws {
    let room = try await builtRoom()
    let glow = try #require(room.glow)
    let index = try #require(room.layout.pieces.firstIndex { $0.piece.kind == .knitPouf })
    let name = GenzRoom.decorName(room.layout.pieces[index], index: index)
    let holder = try #require(room.decor.pieces[name]?.holder)
    let shadow = try #require(glow.pieceShadows.first { $0.index == index })
    #expect(shadow.shadow.parent === holder)

    room.decor.isOn = true
    #expect(room.decor.select(holder))
    room.decor.beginDrag(at: [3.0, 3.35])
    room.decor.drag(to: [3.0, 5.0])
    for _ in 0..<30 { room.stepDecor(1.0 / 60) }
    #expect(holder.position.y > 0.1, "the pouf is lifted while carried")
    let carried = shadow.shadow.position(relativeTo: room.room)
    #expect(abs(carried.y - shadow.height) < 0.001)

    room.decor.endDrag()
    for _ in 0..<120 { room.stepDecor(1.0 / 60) }
    let settled = shadow.shadow.position(relativeTo: room.room)
    #expect(abs(settled.x - 3.0) < 0.01 && abs(settled.z - 5.0) < 0.01)
    #expect(abs(settled.y - shadow.height) < 0.001)
  }

  @Test func theCatsShadowStaysLevelOnTheSeatWhenTheCatLeansOrIsLifted() async throws {
    let room = try await builtRoom()
    let shadow = try #require(room.catShadow)
    // The seat's top as built, under the cat.
    let base = room.rig?.current.flatMap { room.rig?.info[$0]?.base } ?? .sleep
    let ground = room.groundUnderCat(base: base)
    room.fitCatShadow(0.1)
    let resting = shadow.scale(relativeTo: room.room)

    room.catHolder.position.y = ground + room.layout.cat.length * 0.55
    room.catHolder.orientation =
      simd_quatf(angle: 0.7, axis: [0, 1, 0]) * simd_quatf(angle: 0.13, axis: [0, 0, 1])
    room.bodyHeading = 0.7
    room.fitCatShadow(0.1)
    let lifted = shadow.position(relativeTo: room.room)
    #expect(abs(lifted.y - (ground + GenzRoom.catShadowHeight)) < 0.001)
    let up = shadow.orientation(relativeTo: room.room).act([0, 1, 0])
    #expect(simd_distance(up, [0, 1, 0]) < 0.001, "level, not leaning with the cat")
    #expect(shadow.scale(relativeTo: room.room).x < resting.x, "smaller under a lifted cat")
  }

  @Test func theCatsShadowIsLongStandingAndRoundAsleep() {
    let standing = GenzRoom.catShadowFootprint(.stand)
    let asleep = GenzRoom.catShadowFootprint(.sleep)
    #expect(standing.y > standing.x * 1.8)
    #expect(asleep.x == asleep.y)
  }

  @Test func theCatTurnsTheShortWayRoundInsteadOfSnapping() {
    let start: Float = 3.0
    let goal: Float = -3.0
    let next = GenzRoom.turn(start, towards: goal, step: 1.0 / 60)
    #expect(next > start, "across the back, not the long way through the front")
    #expect(next - start < 0.1, "a little each frame")
    var heading = start
    for _ in 0..<30 { heading = GenzRoom.turn(heading, towards: goal, step: 1.0 / 60) }
    #expect(abs(sin(heading) - sin(goal)) < 0.02 && abs(cos(heading) - cos(goal)) < 0.02)
  }

  @Test func aCatPutDownComesDownOntoTheSeatRatherThanDropping() async throws {
    let room = try await builtRoom()
    let seat = room.homeScene.y
    room.dropped = (seat + 0.2, room.clock)
    room.settleDrop()
    #expect(room.catHolder.position.y > seat + 0.19, "still up there the moment it is let go")
    room.dropped = (seat + 0.2, room.clock - Double(GenzRoom.dropLength) / 2)
    room.settleDrop()
    let half = room.catHolder.position.y
    #expect(half > seat && half < seat + 0.2)
    room.dropped = (seat + 0.2, room.clock - 1)
    room.settleDrop()
    #expect(room.catHolder.position.y == seat)
    #expect(room.dropped == nil)
  }

  @Test func shadowsGoWithTheLights() async throws {
    let room = try await builtRoom()
    let glow = try #require(room.glow)
    room.setLighting(.off)
    #expect(glow.pieceShadows.allSatisfy { !$0.shadow.isEnabled })
    room.setLighting(.candle)
    #expect(glow.pieceShadows.allSatisfy { $0.shadow.isEnabled })
  }
}
