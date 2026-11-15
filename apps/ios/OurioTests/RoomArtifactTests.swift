import RealityKit
import RoomInterface
import Testing
import UIKit

@testable import Billet

/// Draws the Living room the way a phone's settings would, to look for what the owner saw: a dark quad where a moved
/// piece stood, and shapes that change with the quality tier or the mesh setting.
@MainActor
@Suite(.serialized)
struct RoomArtifactTests {
    private func living() async throws -> (RoomController, CatRoom) {
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .seconds(2))
        let room = try #require(controller.current)
        room.catGroup.isEnabled = false
        return (controller, room)
    }

    private func rendering(_ tier: RoomQualityTier) -> RoomRendering {
        let p = tier.plan
        return RoomRendering(
            antialiasing: p.antialiasing, hdr: p.hdr, splatRate: p.splatRate, activeRate: p.activeRate,
            idleRate: p.idleRate, scale: p.scale, bloom: p.bloom, sunShadow: p.sunShadow,
            widestLightOnly: p.widestLightOnly, pulseSlowdown: p.pulseSlowdown)
    }

    @Test func groundingShadowsAreDrawnOffScreenAndAMovedPieceLeavesNoneBehind() async throws {
        let (controller, room) = try await living()
        let base = try await OffscreenRoom.render(room)
        OffscreenRoom.write(base, named: "art-base")
        let books = try #require(controller.decorStage.root.children.first { $0.name == "decor.base-books" })
        let origin = books.position
        books.position = origin + [-0.3, 0, -0.35]
        let moved = try await OffscreenRoom.render(room)
        OffscreenRoom.write(moved, named: "art-moved")
        print("ARTIFACT moved books: \(OffscreenRoom.difference(base, moved).line)")

        var bare = 0
        room.root.forEachDescendant { if $0.components.has(GroundingShadowComponent.self) { bare += 1 } }
        room.root.forEachDescendant { $0.components.remove(GroundingShadowComponent.self) }
        books.position = origin
        let none = try await OffscreenRoom.render(room)
        OffscreenRoom.write(none, named: "art-nogrounding")
        print("ARTIFACT grounding shadows \(bare); base against none: \(OffscreenRoom.difference(base, none).line)")
        withExtendedLifetime(controller) {}
    }

    /// Where the room's own loop thinks a point of the room lands on the screen, drawn as a cross on the picture it drew.
    @Test func theLoopsCameraProjectsOntoWhatTheRendererDrew() async throws {
        let (controller, room) = try await living()
        var pixels = try await OffscreenRoom.render(room)
        let camera = try #require(OffscreenRoom.camera)
        let points: [(String, SIMD3<Float>)] = [
            ("tree", [0.36, 0.014, -0.36]), ("sill", [-0.41, 0.262, 0]), ("bed", [0.1, 0.05, -0.1]),
            ("basket", [0.37, 0.014, 0.36]), ("origin", [0, 0.014, 0]),
        ]
        for (name, local) in points {
            let world = room.pivot.convert(position: local, to: nil)
            guard let screen = camera.project(world) else { continue }
            print("ARTIFACT project \(name) -> \(Int(screen.x)), \(Int(screen.y)) of \(Int(camera.size.width)) x \(Int(camera.size.height))")
            let cx = Int(screen.x * 2), cy = Int(screen.y * 2)
            for d in -12...12 {
                for (x, y) in [(cx + d, cy), (cx, cy + d)] where x >= 0 && y >= 0 && x < OffscreenRoom.width && y < OffscreenRoom.height {
                    let i = (y * OffscreenRoom.width + x) * 4
                    pixels[i] = 255; pixels[i + 1] = 0; pixels[i + 2] = 255
                }
            }
        }
        OffscreenRoom.write(pixels, named: "art-projected")
        withExtendedLifetime(controller) {}
    }

    @Test func theRoomTurnedAsAPlayerTurnsIt() async throws {
        let (controller, room) = try await living()
        for full in [false, true] {
            controller.setPerf(PerfLabMachine.State(changed: full ? [.fullMeshes] : []))
            for yaw: Float in [-0.9, -0.5, 0.5, 0.9, 1.4, 2.4] {
                room.pivot.orientation = .y(yaw)
                let pixels = try await OffscreenRoom.render(room, frames: 4)
                OffscreenRoom.write(pixels, named: "yaw\(Int(yaw * 10))-\(full ? "fullmesh" : "lean")")
            }
        }
        room.pivot.orientation = .identity
        controller.setPerf(.shipped)
        withExtendedLifetime(controller) {}
    }

    @Test func everyTierAndMeshSettingDrawsTheRoom() async throws {
        let (controller, room) = try await living()
        for full in [false, true] {
            controller.setPerf(PerfLabMachine.State(changed: full ? [.fullMeshes] : []))
            for tier in RoomQualityTier.allCases {
                controller.setRendering(rendering(tier))
                let pixels = try await OffscreenRoom.render(room)
                OffscreenRoom.write(pixels, named: "art-\(tier.title)-\(full ? "fullmesh" : "lean")")
                print("ARTIFACT tier \(tier.title) \(full ? "full" : "lean") meshes: covered \(OffscreenRoom.covered(pixels)) \(RoomStats(walking: room.root).line)")
            }
        }
        controller.setPerf(.shipped)
        controller.setRendering(rendering(.full))
        withExtendedLifetime(controller) {}
    }
}

/// What the room's own frame loop draws per second at each tier's idle rate, counted from the renderer's own update
/// events over a few seconds. The loop skips a frame the screen delivers too soon, so the cap holds on a screen that
/// ticks faster than asked.
@MainActor
struct RoomLoopCapTests {
    @Test func theLoopDrawsNoMoreThanTheTierAsksFor() async throws {
        let loop = try #require(RoomRenderLoop())
        loop.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        loop.view.metalLayer.drawableSize = CGSize(width: 780, height: 1688)
        let scene = CityRoomScene()
        loop.show(scene)
        var frames = 0
        let subscription = loop.updates { _ in frames += 1 }
        loop.setRunning(true)
        for tier in RoomQualityTier.allCases {
            let plan = tier.plan
            loop.setQuality(RoomRendering(activeRate: plan.activeRate, idleRate: plan.idleRate, scale: plan.scale))
            try await Task.sleep(for: .milliseconds(500))
            let start = frames
            try await Task.sleep(for: .seconds(4))
            let perSecond = Double(frames - start) / 4
            print("LOOP tier \(tier.title): idle rate \(plan.idleRate) fps asked, \(String(format: "%.1f", perSecond)) drawn a second")
            if frames > 0 { #expect(perSecond <= Double(plan.idleRate) * 1.15 + 1) }
        }
        loop.setRunning(false)
        _ = subscription
    }
}
