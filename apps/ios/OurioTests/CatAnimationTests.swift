import Foundation
import Pet
import RealityKit
import Testing
import simd
@testable import Billet

/// Mochi's motion checked on her real splat, skinned on the CPU as SkinSplats.metal does on the GPU: she never goes
/// through the floor, lies down, gets up and sets off without a jump, and stays the same size in every pose.
@MainActor
struct CatAnimationTests {
    /// Every `stride`th opaque splat of a pose's file, with its skin, ready to move by a rig's bone poses.
    struct Sample {
        let centers: [SIMD3<Float>]
        let bones: [SIMD4<UInt8>]
        let weights: [SIMD4<Float>]

        init(_ name: String = "MochiStanding", stride: Int = 9) throws {
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

    private static func rig() throws -> CatRig {
        try CatRig(CatRig.Files(named: "MochiStanding", drawn: false))
    }

    private static func walker(route: [CatWalker.Waypoint] = []) throws -> CatWalker {
        let walker = try CatWalker(group: Entity(), rig: rig(), scale: 1, rests: route.isEmpty ? [0] : [0, 0],
                                   route: route, wandering: false)
        walker.directed = true
        return walker
    }

    private static func fastest(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> Float {
        zip(a, b).map { simd_distance($0, $1) }.max() ?? 0
    }

    @Test func lyingDownAndCurlingUpStayOnTheFloorAndMoveSmoothly() throws {
        let sample = try Sample()
        let walker = try Self.walker()
        var last: [SIMD3<Float>]?
        var lowest = Float.infinity, fastest: Float = 0
        for pose in [NookiRestPose.loaf, .sleep, .loaf, .sit, .sleep, .sit] {
            walker.settle(pose)
            for _ in 0..<150 {
                walker.update(1 / 60)
                let now = sample.posed(walker.rig.poses)
                lowest = min(lowest, now.map(\.y).min() ?? 0)
                if let last { fastest = max(fastest, Self.fastest(now, last)) }
                last = now
            }
            #expect(walker.rest == pose)
        }
        // Model units: 3 mm below the floor at most, and no splat moving more than 14 mm in a 60 fps frame. The tail
        // sweeping round her side is the quickest at about 5; a cut to another splat moves centimeters.
        #expect(lowest > -0.003, "lowest \(lowest)")
        #expect(fastest < 0.014, "fastest \(fastest)")
    }

    @Test func aTripFromSleepRisesFirstStaysOnTheFloorAndNeverJumps() throws {
        let sample = try Sample()
        let walker = try Self.walker(route: [.init(at: [0, 0, 0]), .init(at: [0.4, 0, 0])])
        walker.settle(.sleep)
        for _ in 0..<180 { walker.update(1 / 60) }
        #expect(walker.lying.curl > 0.9)
        walker.trip()
        var last = sample.posed(walker.rig.poses)
        var lowest = Float.infinity, fastest: Float = 0, frames = 0
        for _ in 0..<(60 * 20) where walker.moving {
            walker.update(1 / 60)
            frames += 1
            let now = sample.posed(walker.rig.poses)
            lowest = min(lowest, now.map(\.y).min() ?? 0)
            fastest = max(fastest, Self.fastest(now, last))
            last = now
        }
        #expect(!walker.moving && frames > 60)
        #expect(!walker.lying.isDown)
        #expect(lowest > -0.003, "lowest \(lowest)")
        // Walking moves her model-space splats only by the gait; 15 mm a frame is a brisk paw swing, not a cut.
        #expect(fastest < 0.015, "fastest \(fastest)")
    }

    /// Her head is bound to one bone only, so sitting, lying or asleep it turns and moves but keeps its size, as the
    /// rest of her keeps hers: there is one splat, never another cat swapped in.
    @Test func everyPoseIsTheSameCatAtTheSameSize() throws {
        let files = try CatRig.Files(named: "MochiStanding", drawn: false)
        let sample = try Sample(stride: 40)
        let head = try #require(files.rig.bones.firstIndex { $0.name == "head" })
        let headOnly = sample.centers.indices.filter { sample.bones[$0][0] == head && sample.weights[$0][0] > 0.999 }
        #expect(headOnly.count > 50)
        func size(_ points: [SIMD3<Float>]) -> Float {
            headOnly.dropFirst().map { simd_distance(points[$0], points[headOnly[0]]) }.reduce(0, +)
        }
        let rest = size(sample.centers)
        let walker = try Self.walker()
        for pose in [NookiRestPose.sit, .loaf, .sleep] {
            walker.settle(pose)
            for _ in 0..<240 { walker.update(1 / 60) }
            #expect(abs(size(sample.posed(walker.rig.poses)) / rest - 1) < 1e-3, "\(pose)")
        }
    }

    @Test func aFoldedKneeRestsOnTheFloorAndThePawSlidesOut() throws {
        let rig = try Self.rig()
        let leg = try #require(rig.legs.first { $0.name == "leftHind" })
        let foot = leg.paw
        #expect(Gait.kneeAboveFloor(leg, hip: leg.hip, foot: foot) == foot)
        // The hip low over the paw: the knee would go under the floor.
        let low = leg.hip - [0, 0.07, 0]
        let moved = Gait.kneeAboveFloor(leg, hip: low, foot: foot)
        #expect(moved.y == foot.y)
        #expect(moved != foot)
        let (a, _, _) = Gait.solveLeg(hip: leg.hip, knee: leg.knee, paw: leg.paw, target: moved - low + leg.hip)
        let knee = Pose.about(leg.hip, .x(a)).apply(leg.knee) - leg.hip + low
        #expect(abs(knee.y - Gait.kneeFloor) < 0.001)
        #expect(moved.z < knee.z, "the hind paw lies on the floor in front of the folded knee")
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
