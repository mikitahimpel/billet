import Foundation
import RealityKit
import Testing
import simd
@testable import Billet

/// The projection and the ray the room's own renderer does for the bubble and for taps, which `RealityView` did.
@MainActor
struct RoomCameraTests {
    private func camera() -> RoomCamera {
        let entity = PerspectiveCamera()
        entity.look(at: [0, 0.2, 0], from: [1, 1, 2], relativeTo: nil)
        return RoomCamera(transform: entity.transformMatrix(relativeTo: nil), fovDegrees: 22,
                          size: CGSize(width: 390, height: 844))
    }

    @Test func theCenterOfTheViewLooksAtTheTarget() throws {
        let camera = camera()
        let ray = camera.ray(through: CGPoint(x: 195, y: 422))
        let toTarget = simd_normalize(SIMD3<Float>(0, 0.2, 0) - SIMD3<Float>(1, 1, 2))
        #expect(simd_distance(ray.direction, toTarget) < 1e-4)
        let projected = try #require(camera.project([0, 0.2, 0]))
        #expect(abs(projected.x - 195) < 0.01)
        #expect(abs(projected.y - 422) < 0.01)
    }

    @Test func aRayThroughAPointProjectsBackToIt() throws {
        let camera = camera()
        for point in [CGPoint(x: 20, y: 50), CGPoint(x: 370, y: 800), CGPoint(x: 100, y: 600)] {
            let ray = camera.ray(through: point)
            let back = try #require(camera.project(ray.origin + ray.direction * 2.5))
            #expect(abs(back.x - point.x) < 0.05)
            #expect(abs(back.y - point.y) < 0.05)
        }
    }

    @Test func aPointBehindTheCameraDoesNotProject() {
        #expect(camera().project([3, 2, 6]) == nil)
    }

    @Test func aRayHitsABoxOrMissesIt() throws {
        let origin = SIMD3<Float>(0, 0, 5)
        let forward = SIMD3<Float>(0, 0, -1)
        #expect(RayBox.hit(origin: origin, direction: forward, min: [-1, -1, -1], max: [1, 1, 1]) == 4)
        #expect(RayBox.hit(origin: origin, direction: forward, min: [2, -1, -1], max: [3, 1, 1]) == nil)
        // From inside, and pointing away.
        #expect(RayBox.hit(origin: [0, 0, 0], direction: forward, min: [-1, -1, -1], max: [1, 1, 1]) == 0)
        #expect(RayBox.hit(origin: origin, direction: [0, 0, 1], min: [-1, -1, -1], max: [1, 1, 1]) == nil)
        // Parallel to a slab and outside it.
        #expect(RayBox.hit(origin: [0, 3, 5], direction: forward, min: [-1, -1, -1], max: [1, 1, 1]) == nil)
    }

    @Test func aTouchFindsTheNearestThingThatTakesTaps() throws {
        let room = CatRoom()
        let near = Entity()
        near.position = [0, 0.2, 0.1]
        CatRoom.tappable(near, size: [0.2, 0.2, 0.2], at: .zero)
        let far = Entity()
        far.position = [0, 0.2, -0.3]
        CatRoom.tappable(far, size: [0.3, 0.3, 0.3], at: .zero)
        room.pivot.addChild(far)
        room.pivot.addChild(near)

        let eye = PerspectiveCamera()
        eye.look(at: [0, 0.2, 0], from: [0, 0.2, 2], relativeTo: nil)
        let camera = RoomCamera(transform: eye.transformMatrix(relativeTo: nil), fovDegrees: 22,
                                size: CGSize(width: 400, height: 400))
        #expect(room.target(at: CGPoint(x: 200, y: 200), camera: camera) === near)
        #expect(room.target(at: CGPoint(x: 5, y: 5), camera: camera) == nil)
    }
}

@MainActor
struct RoomCameraPlaneTests {
    @Test func theCenterRayMeetsTheFloorWhereTheCameraLooks() throws {
        let eye = PerspectiveCamera()
        eye.look(at: [0, 0, 0], from: [0, 1, 2], relativeTo: nil)
        let camera = RoomCamera(transform: eye.transformMatrix(relativeTo: nil), fovDegrees: 22,
                                size: CGSize(width: 400, height: 400))
        let floor = try #require(camera.unproject(CGPoint(x: 200, y: 200), ontoPlane: matrix_identity_float4x4))
        #expect(simd_distance(floor, .zero) < 1e-4)
        // Looking above the horizon never meets the floor.
        let sky = PerspectiveCamera()
        sky.look(at: [0, 3, -5], from: [0, 1, 2], relativeTo: nil)
        let up = RoomCamera(transform: sky.transformMatrix(relativeTo: nil), fovDegrees: 22,
                            size: CGSize(width: 400, height: 400))
        #expect(up.unproject(CGPoint(x: 200, y: 200), ontoPlane: matrix_identity_float4x4) == nil)
    }
}
