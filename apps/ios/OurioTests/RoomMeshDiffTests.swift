import RealityKit
import RoomInterface
import Testing
import UIKit

@testable import Billet

/// The lean meshes against RealityKit's, drawn by the same renderer from the same camera: what differs is the edge of a
/// silhouette, a pixel wide, since the room is drawn without antialiasing. Serialized: they set `Meshes.smooth`.
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

    private func report(_ label: String, _ a: [UInt8], _ b: [UInt8]) -> OffscreenRoom.Difference {
        let d = OffscreenRoom.difference(a, b)
        print("DIFF \(label): \(d.line); over 8: \(String(format: "%.4f", d.shareOver8 * 100)) %")
        return d
    }

    @Test func leanBoxesAndSpheresLeaveTheBedroomLookingTheSame() async throws {
        let city = CityRoomScene()
        try await Task.sleep(for: .seconds(2))
        city.catGroup.isEnabled = false
        let full = RoomStats(walking: city.root)
        let a = try await OffscreenRoom.render(city)
        Meshes.retessellate(city.root, smooth: true)
        let lean = RoomStats(walking: city.root)
        let b = try await OffscreenRoom.render(city)
        OffscreenRoom.write(a, named: "bedroom-full")
        OffscreenRoom.write(b, named: "bedroom-lean")
        print("DIFF bedroom tris \(full.triangles) -> \(lean.triangles), parts \(full.parts) -> \(lean.parts)")
        let d = report("bedroom lean meshes", a, b)
        // A machine with no GPU draws an empty frame; the comparison then has nothing to say.
        guard OffscreenRoom.covered(a) > 0.5 else { return }
        #expect(lean.parts == full.parts && lean.models == full.models)
        #expect(lean.triangles * 30 < full.triangles)
        #expect(d.shareOver8 <= Self.allowedShare)
        Meshes.retessellate(city.root, smooth: false)
        #expect(RoomStats(walking: city.root).triangles == full.triangles)
    }

    @Test func leanMeshesAndModelsLeaveTheLivingRoomLookingTheSame() async throws {
        Meshes.smooth = false
        let (fullController, full) = try await living()
        let fullStats = RoomStats(walking: full.root)
        let a = try await OffscreenRoom.render(full)
        OffscreenRoom.write(a, named: "living-full")

        Meshes.smooth = true
        defer { Meshes.smooth = false }
        let (leanController, lean) = try await living()
        let leanStats = RoomStats(walking: lean.root)
        let b = try await OffscreenRoom.render(lean)
        OffscreenRoom.write(b, named: "living-lean")
        print("DIFF living tris \(fullStats.triangles) -> \(leanStats.triangles), parts \(fullStats.parts) -> \(leanStats.parts), models \(fullStats.models) -> \(leanStats.models), grounding \(fullStats.groundingCasters) -> \(leanStats.groundingCasters)")
        let d = report("living lean meshes and models", a, b)
        guard OffscreenRoom.covered(a) > 0.5 else { return }
        #expect(leanStats.triangles * 5 < fullStats.triangles)
        #expect(d.shareOver8 <= Self.allowedShare)
        withExtendedLifetime((fullController, leanController)) {}
    }

    @Test func noEntityWithoutAModelCarriesAGroundingShadow() async throws {
        Meshes.smooth = false
        let (controller, room) = try await living()
        var bare = 0
        room.root.forEachDescendant { entity in
            if entity.components.has(GroundingShadowComponent.self), !entity.components.has(ModelComponent.self) { bare += 1 }
        }
        #expect(bare == 0)
        withExtendedLifetime(controller) {}
    }

    @Test func theLabsSwitchMakesBothRoomsLeanAtOnceAndBringsBackTheOriginals() async throws {
        Meshes.smooth = false
        defer { Meshes.smooth = false }
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        controller.prepare(.city)
        controller.showDecor(controller.decor)
        let home = try #require(controller.home)
        let city = try #require(controller.city)
        for _ in 0..<200 where RoomStats(walking: city.root).blobs == 0 { try await Task.sleep(for: .milliseconds(50)) }
        let homeBefore = RoomStats(walking: home.root), cityBefore = RoomStats(walking: city.root)

        controller.setPerf(PerfLabMachine.State(changed: [.leanMeshes]))
        let homeLean = RoomStats(walking: home.root), cityLean = RoomStats(walking: city.root)
        print("room perf: lean meshes living \(homeBefore.triangles) -> \(homeLean.triangles), bedroom \(cityBefore.triangles) -> \(cityLean.triangles)")
        #expect(homeLean.triangles * 2 < homeBefore.triangles)
        #expect(cityLean.triangles * 30 < cityBefore.triangles)
        #expect(homeLean.models == homeBefore.models && homeLean.parts == homeBefore.parts)
        #expect(cityLean.models == cityBefore.models && cityLean.parts == cityBefore.parts)

        controller.setPerf(.shipped)
        #expect(RoomStats(walking: home.root).triangles == homeBefore.triangles)
        #expect(RoomStats(walking: city.root).triangles == cityBefore.triangles)
    }
}
