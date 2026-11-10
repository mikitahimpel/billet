import Foundation
import Pet
import RealityKit
import Testing
import simd
@testable import Billet

/// Mochi's motion checked on her real splats, skinned on the CPU as SkinSplats.metal does on the GPU: she never goes
/// through the floor, lies down and gets up without a jump, and the swap between her two splats lands the seated one
/// where the standing one was.
@MainActor
struct CatAnimationTests {
    /// Every `stride`th opaque splat of a pose's file, with its skin, ready to move by a rig's bone poses.
    struct Sample {
        let centers: [SIMD3<Float>]
        let bones: [SIMD4<UInt8>]
        let weights: [SIMD4<Float>]

        init(_ name: String, stride: Int = 9) throws {
            let file = try SplatLoader.read(named: name)
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "skin"))
            let skin = try [UInt8](Data(contentsOf: url))
            var centers: [SIMD3<Float>] = [], bones: [SIMD4<UInt8>] = [], weights: [SIMD4<Float>] = []
            for i in Swift.stride(from: 0, to: file.count, by: stride) where file.still[8 * i + 3] > 0 {
                centers.append([file.moving[8 * i], file.moving[8 * i + 1], file.moving[8 * i + 2]])
                bones.append([skin[8 * i], skin[8 * i + 1], skin[8 * i + 2], skin[8 * i + 3]])
                weights.append(SIMD4(Float(skin[8 * i + 4]), Float(skin[8 * i + 5]), Float(skin[8 * i + 6]),
                                     Float(skin[8 * i + 7])) / 255)
            }
            self.centers = centers
            self.bones = bones
            self.weights = weights
        }

        /// The centers moved by `poses` with dual quaternion blending, as the GPU moves them.
        func posed(_ poses: [Pose]) -> [SIMD3<Float>] {
            let dual = poses.map(DualQuat.init)
            return centers.indices.map { i in
                let first = dual[Int(bones[i][0])].real
                var real = SIMD4<Float>.zero, du = SIMD4<Float>.zero
                for k in 0..<4 {
                    let bone = dual[Int(bones[i][k])]
                    let w = simd_dot(bone.real, first) < 0 ? -weights[i][k] : weights[i][k]
                    real += w * bone.real
                    du += w * bone.dual
                }
                let n = simd_length(real)
                let q = simd_quatf(vector: real / n)
                let t = 2 * (simd_quatf(vector: du / n) * q.conjugate).imag
                return q.act(centers[i]) + t
            }
        }
    }

    private static func rig(_ name: String) throws -> CatRig {
        try CatRig(CatRig.Files(named: name, drawn: false))
    }

    private static func walker(route: [CatWalker.Waypoint] = []) throws -> CatWalker {
        let walker = try CatWalker(group: Entity(), standing: rig("MochiStanding"), seated: rig("Mochi"), scale: 1,
                                   rests: route.isEmpty ? [0] : [0, 0], route: route, wandering: false)
        walker.directed = true
        return walker
    }

    /// The splats of whichever splat shows, in the walker's model space: the seated one sits `mount` from the standing.
    private static func shown(_ walker: CatWalker, standing: Sample, seated: Sample) -> [SIMD3<Float>] {
        walker.seatedShows
            ? seated.posed(walker.seated.poses).map { $0 + walker.seated.mount }
            : standing.posed(walker.standing.poses)
    }

    @Test func lyingDownAndCurlingUpStayOnTheFloorAndMoveSmoothly() throws {
        let seated = try Sample("Mochi"), standing = try Sample("MochiStanding")
        let walker = try Self.walker()
        var last: [SIMD3<Float>]?
        var lowest = Float.infinity, fastest: Float = 0
        for pose in [NookiRestPose.loaf, .sleep, .loaf, .sit, .sleep, .sit] {
            walker.settle(pose)
            for _ in 0..<150 {
                walker.update(1 / 60)
                let now = Self.shown(walker, standing: standing, seated: seated)
                lowest = min(lowest, now.map(\.y).min() ?? 0)
                if let last { fastest = max(fastest, zip(now, last).map { simd_distance($0, $1) }.max() ?? 0) }
                last = now
            }
            #expect(walker.rest == pose)
        }
        #expect(walker.seatedShows)
        // Model units: 3 mm below the floor at most, and no splat moving more than 8 mm in a 60 fps frame, which her
        // quickest glance stays under and a cut between two splats (centimeters) does not.
        #expect(lowest > -0.003, "lowest \(lowest)")
        #expect(fastest < 0.008, "fastest \(fastest)")
    }

    @Test func aTripFromLyingStaysOnTheFloorAndTheSwapLandsHeadOnHead() throws {
        let seated = try Sample("Mochi"), standing = try Sample("MochiStanding")
        let walker = try Self.walker(route: [.init(at: [0, 0, 0]), .init(at: [0.4, 0, 0])])
        walker.settle(.sleep)
        for _ in 0..<180 { walker.update(1 / 60) }
        #expect(walker.lying.curl > 0.9)
        walker.trip()
        var lowest = Float.infinity, eyeJump: Float = 0, swaps = 0
        var eyes = walker.eyes, showing = walker.seatedShows
        for _ in 0..<(60 * 20) where walker.moving || walker.lying.isDown {
            walker.update(1 / 60)
            let now = Self.shown(walker, standing: standing, seated: seated)
            lowest = min(lowest, now.map(\.y).min() ?? 0)
            if walker.seatedShows != showing {
                swaps += 1
                showing = walker.seatedShows
                eyeJump = max(eyeJump, simd_distance(walker.eyes, eyes))
                #expect(!walker.lying.isDown, "she swaps splats sitting up")
            }
            eyes = walker.eyes
        }
        #expect(!walker.moving)
        #expect(swaps == 2, "stands up off the seated splat, sits back down on it")
        #expect(lowest > -0.003, "lowest \(lowest)")
        #expect(eyeJump < 0.006, "eyes jump \(eyeJump) at a swap")
    }

    @Test func theStandingSplatSittingHasTheSeatedSilhouette() throws {
        let seated = try Sample("Mochi", stride: 40), standing = try Sample("MochiStanding", stride: 40)
        let walker = try Self.walker(route: [.init(at: [0, 0, 0]), .init(at: [0.4, 0, 0])])
        walker.trip()
        // The frame before the seated splat shows again at the far end: the standing one in the sit posture.
        var before: [SIMD3<Float>] = [], showing = walker.seatedShows
        for _ in 0..<(60 * 20) where walker.moving {
            if !walker.seatedShows { before = standing.posed(walker.standing.poses) }
            walker.update(1 / 60)
            if walker.seatedShows && !showing { break }
            showing = walker.seatedShows
        }
        let after = seated.posed(walker.seated.poses).map { $0 + walker.seated.mount }
        func nearest(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> Float {
            a.map { p in b.map { simd_distance(p, $0) }.min() ?? 0 }.reduce(0, +) / Float(a.count)
        }
        // Mean distance to the other cloud's nearest splat, both ways: under 1.5 cm on a 30 cm cat.
        let chamfer = nearest(before, after) + nearest(after, before)
        #expect(chamfer < 0.015, "chamfer \(chamfer)")
    }

    @Test func aFoldedKneeRestsOnTheFloorAndThePawSlidesOut() throws {
        let rig = try Self.rig("MochiStanding")
        let leg = try #require(rig.legs.first { $0.name == "leftHind" })
        let foot = leg.paw
        #expect(Gait.kneeAboveFloor(leg, hip: leg.hip, foot: foot) == foot)
        // The hip low over the paw: the knee would go under the floor.
        let low = leg.hip - [0, 0.07, 0]
        let moved = Gait.kneeAboveFloor(leg, hip: low, foot: foot)
        #expect(moved.y == foot.y)
        #expect(moved.z < foot.z, "the hind paw slides forward")
        let (a, _, _) = Gait.solveLeg(hip: leg.hip, knee: leg.knee, paw: leg.paw, target: moved - low + leg.hip)
        let knee = Pose.about(leg.hip, .x(a)).apply(leg.knee) - leg.hip + low
        #expect(abs(knee.y - Gait.kneeFloor) < 0.001)
    }

    @Test func lyingEasesToItsTargetWithoutOvershootAndRisesBackToSitting() {
        var lying = Lying()
        var highest: Float = 0
        for _ in 0..<240 {
            lying.update(1 / 60, toward: .sleep)
            highest = max(highest, lying.loaf, lying.curl)
        }
        #expect(highest < 1.0005)
        #expect(lying.loaf > 0.99 && lying.curl > 0.99)
        for _ in 0..<240 { lying.update(1 / 60, toward: .loaf) }
        #expect(lying.loaf > 0.99 && lying.curl < 0.01)
        let from = lying
        lying.rise(from: from, 0.5)
        #expect(abs(lying.loaf - 0.5 * from.loaf) < 1e-4)
        lying.rise(from: from, 1)
        #expect(!lying.isDown)
    }
}
