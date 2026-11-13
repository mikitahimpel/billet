import Foundation
import Testing

@testable import Billet

struct CameraFollowTests {
    @Test func theCameraTargetHoldsWhereverTheCatWalks() {
        let room: SIMD3<Float> = [0, 0.1, 0]
        let spots: [SIMD3<Float>] = [[0.3, 0.1, -0.2], [-0.4, 0.2, 0.3], [0.06, 0.12, -0.04]]
        for zoom in [Float(0), 0.25, 1] {
            for cat in spots {
                #expect(CameraFollow.target(framing: room, cat: cat, zoom: zoom, follow: 0) == room)
            }
        }
    }

    @Test func aCameraThatFollowsDrawsTowardHerByTheZoom() {
        let room: SIMD3<Float> = [0, 0, 0]
        let cat: SIMD3<Float> = [1, 0, 0]
        #expect(CameraFollow.target(framing: room, cat: cat, zoom: 0.5, follow: 1) == [0.5, 0, 0])
        #expect(CameraFollow.target(framing: room, cat: cat, zoom: 0.5, follow: 0.5) == [0.25, 0, 0])
    }

    @Test func followingEasesInAndBackOut() {
        var follow: Float = 0
        for _ in 0..<300 { follow = CameraFollow.follow(follow, active: true, dt: 1 / 60) }
        #expect(follow == 1)
        let step = CameraFollow.follow(1, active: false, dt: 1 / 60)
        #expect(step < 1 && step > 0.9)
        for _ in 0..<600 { follow = CameraFollow.follow(follow, active: false, dt: 1 / 60) }
        #expect(follow == 0)
    }

    @Test func aJitteringPointMovesLessThanItsInput() {
        var smoother = ScreenSmoother()
        var last = smoother.step(CGPoint(x: 200, y: 300), dt: 1 / 60)
        var worst: CGFloat = 0
        for frame in 0..<120 {
            let jitter: CGFloat = frame.isMultiple(of: 2) ? 2 : -2
            let out = smoother.step(CGPoint(x: 200 + jitter, y: 300 - jitter), dt: 1 / 60)
            if frame > 30 { worst = max(worst, hypot(out.x - last.x, out.y - last.y)) }
            last = out
        }
        // The input jumps 5.7 points a frame; the output stays under a point.
        #expect(worst < 1)
    }

    @Test func aPointThatStopsRestsOnThePixelGridAndAMovingOneTrailsLittle() {
        var smoother = ScreenSmoother()
        var out = smoother.step(CGPoint(x: 100, y: 100), dt: 1 / 60)
        for _ in 0..<300 { out = smoother.step(CGPoint(x: 150.1234, y: 80.4321), dt: 1 / 60) }
        #expect(abs(out.x * 3 - (out.x * 3).rounded()) < 0.0001)
        #expect(abs(out.x - 150.1234) < 0.2)
        var runner = ScreenSmoother()
        var point = runner.step(CGPoint.zero, dt: 1 / 60)
        for frame in 1...120 { point = runner.step(CGPoint(x: CGFloat(frame) * 3, y: 0), dt: 1 / 60) }
        #expect(360 - point.x < 15)
    }

    @Test func aPointFarFromTheLastOneJumpsThere() {
        var smoother = ScreenSmoother()
        _ = smoother.step(CGPoint(x: 10, y: 10), dt: 1 / 60)
        #expect(smoother.step(CGPoint(x: 300, y: 600), dt: 1 / 60) == CGPoint(x: 300, y: 600))
    }
}
