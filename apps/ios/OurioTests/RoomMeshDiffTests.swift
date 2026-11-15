import RealityKit
import RoomInterface
import Testing
import UIKit

@testable import Billet

/// The lean meshes the rooms are built with, against RealityKit's own, drawn by the same renderer from the same camera:
/// what differs is the edge of a silhouette, a pixel wide, since the room is drawn without antialiasing. The tests
/// retessellate the scene they built and never set `Meshes.smooth`, which the other suites read.
@MainActor
@Suite(.serialized)
struct RoomMeshDiffTests {
    /// The share of pixels more than 8 of 255 off in a channel: the gallery's own match (`Snapshot.pixelTolerance`).
    private static let allowedShare = 0.005

    private func living() async throws -> (RoomController, CatRoom) {
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .seconds(2))
        let room = try #require(controller.current)
        room.catGroup.isEnabled = false
        return (controller, room)
    }

    private func compare(_ label: String, _ room: CatRoom) async throws {
        Meshes.retessellate(room.root, smooth: false)
        let full = RoomStats(walking: room.root)
        let a = try await OffscreenRoom.render(room)
        Meshes.retessellate(room.root, smooth: true)
        let lean = RoomStats(walking: room.root)
        let b = try await OffscreenRoom.render(room)
        OffscreenRoom.write(a, named: label + "-full")
        OffscreenRoom.write(b, named: label + "-lean")
        let d = OffscreenRoom.difference(a, b)
        print("DIFF \(label) tris \(full.triangles) -> \(lean.triangles), parts \(full.parts) -> \(lean.parts); \(d.line); over 8: \(String(format: "%.4f", d.shareOver8 * 100)) %")
        // A machine with no GPU draws an empty frame; the comparison then has nothing to say.
        guard OffscreenRoom.covered(a) > 0.5 else { return }
        #expect(lean.parts == full.parts && lean.models == full.models)
        #expect(lean.triangles * 5 < full.triangles)
        #expect(d.shareOver8 <= Self.allowedShare)
        Meshes.retessellate(room.root, smooth: false)
        #expect(RoomStats(walking: room.root).triangles == full.triangles)
        Meshes.retessellate(room.root, smooth: true)
    }

    @Test func leanBoxesAndSpheresLeaveTheBedroomLookingTheSame() async throws {
        let city = CityRoomScene()
        try await Task.sleep(for: .seconds(2))
        city.catGroup.isEnabled = false
        try await compare("bedroom", city)
    }

    @Test func leanBoxesAndSpheresLeaveTheLivingRoomLookingTheSame() async throws {
        let (controller, room) = try await living()
        try await compare("living", room)
        withExtendedLifetime(controller) {}
    }

    /// A piece's grounding shadow sits on every entity of its model, the nodes with no mesh too, as it did when the pieces
    /// were first made movable: on a phone, a piece moved away left a black quad at its old place when only the mesh
    /// entities carried it.
    @Test func everyEntityOfACastingPieceCarriesItsGroundingShadow() async throws {
        let (controller, room) = try await living()
        let holder = try #require(controller.decorStage.root.children.first { $0.name == "decor.base-nightstand" })
        let piece = try #require(holder.children.first { !$0.components.has(ModelComponent.self) })
        var bare = 0, total = 0
        piece.forEachDescendant { entity in
            total += 1
            if !entity.components.has(GroundingShadowComponent.self) { bare += 1 }
        }
        print("GROUNDING nightstand entities \(total) without a shadow \(bare)")
        #expect(total > 0 && bare == 0)
        withExtendedLifetime(controller) {}
    }

    @Test func theLabsSwitchBringsBackRealityKitsMeshesAndTheLeanOnesAgain() async throws {
        defer { Meshes.smooth = true }
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        controller.prepare(.city)
        controller.showDecor(controller.decor)
        let home = try #require(controller.home)
        let city = try #require(controller.city)
        for _ in 0..<200 where RoomStats(walking: city.root).blobs == 0 { try await Task.sleep(for: .milliseconds(50)) }
        Meshes.retessellate(home.root, smooth: true)
        Meshes.retessellate(city.root, smooth: true)
        let homeLean = RoomStats(walking: home.root), cityLean = RoomStats(walking: city.root)

        controller.setPerf(PerfLabMachine.State(changed: [.fullMeshes]))
        let homeFull = RoomStats(walking: home.root), cityFull = RoomStats(walking: city.root)
        print("room perf: full meshes living \(homeLean.triangles) -> \(homeFull.triangles), bedroom \(cityLean.triangles) -> \(cityFull.triangles)")
        #expect(homeFull.triangles > homeLean.triangles * 3)
        #expect(cityFull.triangles > cityLean.triangles * 30)
        #expect(homeFull.models == homeLean.models && homeFull.parts == homeLean.parts)
        #expect(cityFull.models == cityLean.models && cityFull.parts == cityLean.parts)

        controller.setPerf(.shipped)
        #expect(RoomStats(walking: home.root).triangles == homeLean.triangles)
        #expect(RoomStats(walking: city.root).triangles == cityLean.triangles)
    }
}
