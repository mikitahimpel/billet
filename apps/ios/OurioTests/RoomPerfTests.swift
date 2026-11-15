import DecorInterface
import RealityKit
import RoomInterface
import Testing

@testable import Billet

/// Labs → Performance's room switches: what each takes out of the scene, counted with the room stats, and that
/// switching it off gives the scene back as it was.
@MainActor
struct RoomPerfTests {
    private func switches(_ change: (inout RoomPerfSwitches) -> Void) -> RoomPerfSwitches {
        var value = RoomPerfSwitches()
        change(&value)
        return value
    }

    @Test func allStartOff() {
        #expect(RoomPerfSwitches(.shipped) == RoomPerfSwitches())
        #expect(RoomPerfSwitches() == switches { _ in })
    }

    @Test func fewerLightsKeepsTheWidestAndGivesTheOthersBack() {
        for (name, room) in [("living", DioramaScene() as CatRoom), ("bedroom", CityRoomScene())] {
            let perf = RoomPerfCoordinator()
            let before = RoomStats(walking: room.root)
            #expect(before.point >= 3, "\(name) has point lights")
            _ = perf.set(switches { $0.fewerLights = true })
            perf.lights(in: room)
            let after = RoomStats(walking: room.root)
            print("room perf: \(name) point lights \(before.point) -> \(after.point)")
            #expect(after.point == 1)
            _ = perf.set(RoomPerfSwitches())
            perf.lights(in: room)
            #expect(RoomStats(walking: room.root).point == before.point)
        }
    }

    /// A rough measure of how lit a room is: the point lights that are on and their summed intensity, the ambient light's
    /// strength in stops, and whether the glow pass is on.
    private struct Brightness {
        var lamps = 0
        var lumens: Float = 0
        var ambientStops: Float = 0

        init(_ room: CatRoom) {
            func visit(_ entity: Entity) {
                if entity.isEnabled, let point = entity.components[PointLightComponent.self], point.intensity > 0 {
                    lamps += 1
                    lumens += point.intensity
                }
                if let ibl = entity.components[ImageBasedLightComponent.self] { ambientStops = ibl.intensityExponent }
                entity.children.forEach(visit)
            }
            visit(room.root)
        }
    }

    @Test func noTierLeavesTheBedroomDarkerThanFullByNight() {
        let room = CityRoomScene()
        room.lampsFade = false
        room.lampChoice = true
        for _ in 0..<5 { room.tick(1.0 / 60) }
        let perf = RoomPerfCoordinator()
        func look(_ tier: RoomQualityTier) -> Brightness {
            let plan = tier.plan
            _ = perf.set(switches {
                $0.noSunShadow = !plan.sunShadow
                $0.fewerLights = plan.widestLightOnly
                $0.noBloom = !plan.bloom
            })
            room.ambientLift = Float(plan.ambientLift)
            perf.lights(in: room)
            return Brightness(room)
        }
        let full = look(.full)
        #expect(full.lamps >= 3)
        for tier in RoomQualityTier.allCases {
            let now = look(tier)
            #expect(now.lamps == full.lamps, "\(tier) keeps every lamp")
            #expect(now.lumens >= full.lumens, "\(tier) keeps the lamps' light")
            #expect(now.ambientStops >= full.ambientStops, "\(tier) keeps the ambient light")
        }
    }

    @Test func theLampsFadeAndAChoiceOverridesTheHour() {
        let room = CityRoomScene()
        room.lampsFade = false
        room.lampChoice = false
        for _ in 0..<5 { room.tick(1.0 / 60) }
        let off = Brightness(room)
        room.lampChoice = true
        for _ in 0..<5 { room.tick(1.0 / 60) }
        let on = Brightness(room)
        #expect(on.lumens > off.lumens)
        #expect(on.ambientStops >= off.ambientStops)
        room.lampsFade = true
        room.lampChoice = false
        room.tick(1.0 / 60)
        let midway = Brightness(room)
        #expect(midway.lumens < on.lumens && midway.lumens > off.lumens)
        for _ in 0..<600 { room.tick(1.0 / 60) }
        #expect(Brightness(room).lumens <= off.lumens + 1)
    }

    @Test func noSunShadowTakesTheShadowMapOutAndBack() {
        for (name, room) in [("living", DioramaScene() as CatRoom), ("bedroom", CityRoomScene())] {
            let perf = RoomPerfCoordinator()
            let before = RoomStats(walking: room.root)
            #expect(before.shadowMaps >= 1)
            _ = perf.set(switches { $0.noSunShadow = true })
            perf.lights(in: room)
            let off = RoomStats(walking: room.root)
            print("room perf: \(name) shadow maps \(before.shadowMaps) -> \(off.shadowMaps)")
            #expect(off.shadowMaps == 0)
            #expect(off.directional == before.directional)
            _ = perf.set(RoomPerfSwitches())
            perf.lights(in: room)
            #expect(RoomStats(walking: room.root).shadowMaps == before.shadowMaps)
        }
    }

    private func loadedHome() async throws -> RoomController {
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !(controller.isReady && controller.home?.iblReceiver != nil) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.isReady)
        return controller
    }

    private func wait(_ controller: RoomController, until done: (RoomStats) -> Bool) async throws -> RoomStats {
        var stats = try #require(controller.roomStats(tier: .full))
        for _ in 0..<800 where !done(stats) {
            try await Task.sleep(for: .milliseconds(50))
            stats = try #require(controller.roomStats(tier: .full))
        }
        return stats
    }

    @Test func mergedFurnitureDrawsTheSameTrianglesInFewerPartsAndSplitsForDecorate() async throws {
        let controller = try await loadedHome()
        let before = try #require(controller.roomStats(tier: .full))
        controller.setPerf(PerfLabMachine.State(changed: [.mergeFurniture]))
        let merged = try await wait(controller) { $0.mergedModels > 0 }
        print("room perf: merge count \(before.models) models, merged \(merged.mergedModels)")
        print("room perf: merge rejected \(FurnitureMerge.rejected)")
        print("room perf: merge before \(before.line)")
        print("room perf: merge after  \(merged.line)")
        #expect(merged.mergedModels > 0)
        #expect(merged.parts < before.parts)
        #expect(merged.triangles == before.triangles)

        // Arranging gives every piece its own model back at once.
        let layout = controller.decor.layout
        controller.showDecor(RoomDecor(layout: layout, mode: .arranging(selected: nil, fits: true)))
        let arranging = try #require(controller.roomStats(tier: .full))
        #expect(arranging.mergedModels == 0)
        #expect(arranging.parts == before.parts)
        #expect(arranging.triangles == before.triangles)

        // Closed again, it merges once more; switched off, the scene is as it was.
        controller.showDecor(RoomDecor(layout: layout))
        let again = try await wait(controller) { $0.mergedModels > 0 }
        #expect(again.parts == merged.parts)
        controller.setPerf(.shipped)
        let off = try #require(controller.roomStats(tier: .full))
        #expect(off.mergedModels == 0)
        #expect(off.parts == before.parts && off.models == before.models && off.triangles == before.triangles)
        #expect(off.groundingCasters == before.groundingCasters)
    }

    @Test func aMovedPieceMergesAgainForItsNewPlace() async throws {
        let controller = try await loadedHome()
        controller.setPerf(PerfLabMachine.State(changed: [.mergeFurniture]))
        _ = try await wait(controller) { $0.mergedModels > 0 }
        let layout = controller.decor.layout
        let first = try #require(layout.standing.first)
        controller.showDecor(RoomDecor(layout: DecorLayout(placements: layout.placements, stored: layout.stored.union([first.item]))))
        let stowed = try #require(controller.roomStats(tier: .full))
        #expect(stowed.mergedModels == 0, "a changed layout is split at once, so no stale copy of the stowed piece shows")
        let after = try await wait(controller) { $0.mergedModels > 0 }
        #expect(after.mergedModels > 0)
    }

    @Test func theBakedLayerReplacesEveryBlobWithOneQuadAndTheBlobsComeBack() async throws {
        let controller = try await loadedHome()
        let before = try #require(controller.roomStats(tier: .full))
        #expect(before.blobs > 0 && before.blobLayers == 0)
        controller.setPerf(PerfLabMachine.State(changed: [.bakedBlobs]))
        let baked = try await wait(controller) { $0.blobLayers > 0 }
        print("room perf: blobs \(before.blobs) -> \(baked.blobs) + \(baked.blobLayers) layer, models \(before.models) -> \(baked.models)")
        #expect(baked.blobLayers == 1 && baked.blobs == 0)
        #expect(baked.models == before.models - before.blobs + 1)

        let layout = controller.decor.layout
        controller.showDecor(RoomDecor(layout: layout, mode: .arranging(selected: nil, fits: true)))
        let arranging = try #require(controller.roomStats(tier: .full))
        #expect(arranging.blobs == before.blobs && arranging.blobLayers == 0)
        controller.showDecor(RoomDecor(layout: layout))
        _ = try await wait(controller) { $0.blobLayers > 0 }
        controller.setPerf(.shipped)
        let off = try #require(controller.roomStats(tier: .full))
        #expect(off.blobs == before.blobs && off.blobLayers == 0 && off.models == before.models)
    }

    @Test func theBedroomsPiecesMergeToo() async throws {
        let controller = try await loadedHome()
        controller.prepare(.city)
        controller.showDecor(controller.decor)
        let city = try #require(controller.city)
        func stats() -> RoomStats { RoomStats(walking: city.root, room: "bedroom") }
        for _ in 0..<400 where stats().blobs == 0 { try await Task.sleep(for: .milliseconds(50)) }
        let before = stats()
        print("room perf: bedroom before \(before.line)")
        controller.setPerf(PerfLabMachine.State(changed: [.mergeFurniture, .bakedBlobs]))
        for _ in 0..<400 where stats().mergedModels == 0 { try await Task.sleep(for: .milliseconds(50)) }
        let merged = stats()
        print("room perf: bedroom merged \(FurnitureMerge.rejected) \(merged.line)")
        #expect(merged.mergedModels > 0)
        // The blobs' quads leave and the baked layer's two triangles come.
        #expect(abs(merged.triangles - before.triangles) <= 8)
        #expect(merged.parts < before.parts)
        #expect(merged.blobs == 0 && merged.blobLayers == 1)
        controller.setPerf(.shipped)
        let off = stats()
        #expect(off.parts == before.parts && off.triangles == before.triangles && off.blobs == before.blobs)
    }
}
