import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzShadowTests {
  private func builtRoom() async throws -> GenzRoom {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: .cosyNook))
    let room = GenzRoomCache(suite: "genz-shadow-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(60)
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

  @Test func shadowsGoWithTheLights() async throws {
    let room = try await builtRoom()
    let glow = try #require(room.glow)
    room.setLighting(.off)
    #expect(glow.pieceShadows.allSatisfy { !$0.shadow.isEnabled })
    room.setLighting(.candle)
    #expect(glow.pieceShadows.allSatisfy { $0.shadow.isEnabled })
  }
}
