import Foundation
import Metal
import RealityKit
import simd
import Synchronization

/// A rigid motion x' = q x + t.
nonisolated struct Pose {
    var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var t = SIMD3<Float>.zero

    /// Rotation by q about a pivot point.
    static func about(_ pivot: SIMD3<Float>, _ q: simd_quatf) -> Pose {
        Pose(q: q, t: pivot - q.act(pivot))
    }

    /// self after parent: x' = parent(self(x)).
    func under(_ parent: Pose) -> Pose {
        Pose(q: parent.q * q, t: parent.q.act(t) + parent.t)
    }

    var inverse: Pose {
        let inv = q.inverse
        return Pose(q: inv, t: inv.act(-t))
    }

    func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        q.act(p) + t
    }

    /// `t` of the way from self to `other`.
    func mix(_ other: Pose, _ t: Float) -> Pose {
        Pose(q: simd_slerp(q, other.q, t), t: simd_mix(self.t, other.t, SIMD3(repeating: t)))
    }
}

/// A <name>.rig.json sidecar from nooki-scene/generate/skin.py: bones in skin order, model space.
nonisolated struct RigFile: Decodable {
    nonisolated struct Bone: Decodable {
        let name: String
        let parent: String?
        let head: SIMD3<Float>
        let tail: SIMD3<Float>
    }

    let bones: [Bone]
    /// Model-space point between the eyes.
    let eyes: SIMD3<Float>?
    /// Where the seated splat sits in the standing one's model space.
    let mount: SIMD3<Float>?
}

/// Mochi's skeletons, ported from nooki-scene/src/three/catRig.js: a two-part spine, head with ears and lids, a tail
/// and, standing, two bones per leg, skinned by dual quaternions on the GPU from the generation pipeline's
/// <name>.rig.json and <name>.skin. Where the GPU can't draw splats the skeleton still poses, with nothing to skin, so
/// the motion around it runs the same.
final class CatRig {
    struct TailJoint {
        var sway: Float = 0
        var lift: Float = 0
        var lean: Float = 0
    }

    /// Set by whoever animates her each frame, in model space; angles in radians, lids from 0 open to 1 shut.
    /// The whole body pitches nose up (+) and rolls about the spine's middle, rises by `lift` and moves back by `back`;
    /// the spine sags by `bend`, chest and rump both up for positive values, and the rump swings by `wiggle` to her left.
    /// `chestMove` and `hipsMove` are laid over the result in model space. The head turns on the neck, hung `headSeat`
    /// of the way from the chest to where the seated skeleton holds it, and then moves by `headShift`.
    /// `feet` are where the paws should be, in `legs` order; a leg that cannot reach stretches toward its paw.
    struct Posture {
        var lift: Float = 0, back: Float = 0, pitch: Float = 0, roll: Float = 0, bend: Float = 0, wiggle: Float = 0
        var headYaw: Float = 0
        var headPitch: Float = 0
        var headRoll: Float = 0
        var headShift = SIMD3<Float>.zero
        var headSeat: Float = 0
        var chestMove = Pose()
        var hipsMove = Pose()
        var earLeft: Float = 0
        var earRight: Float = 0
        var earsBack: Float = 0
        var earTurnLeft: Float = 0
        var earTurnRight: Float = 0
        var lidLeft: Float = 0
        var lidRight: Float = 0
        var tail: [TailJoint]
        var feet: [SIMD3<Float>]
    }

    /// A leg: where it leaves the body, the elbow or knee, and the paw's center on the floor, at rest.
    struct Leg {
        let name: String
        let hip, knee, paw: SIMD3<Float>
        /// Hangs from the chest; otherwise from the hips.
        let fore: Bool
        let upper, lower: Int
    }

    nonisolated enum Failure: Error {
        case missing(String)
        case mismatch(String)
    }

    /// A rig's files read and checked, off the main actor; the splat and its skin only where splats are drawn.
    nonisolated struct Files {
        let rig: RigFile
        let splat: SplatLoader.File?
        let skin: [UInt8]?

        init(named name: String, drawn: Bool, in bundle: Bundle = .main) throws {
            guard let rigURL = bundle.url(forResource: "\(name).rig", withExtension: "json") else { throw Failure.missing(name) }
            let rig = try JSONDecoder().decode(RigFile.self, from: Data(contentsOf: rigURL))
            guard rig.bones.count < 256 else { throw Failure.mismatch(name) }
            self.rig = rig
            guard drawn else {
                splat = nil
                skin = nil
                return
            }
            guard let skinURL = bundle.url(forResource: name, withExtension: "skin") else { throw Failure.missing(name) }
            let splat = try SplatLoader.read(named: name, in: bundle)
            let skin = try [UInt8](Data(contentsOf: skinURL))
            guard skin.count == splat.count * 8 else { throw Failure.mismatch(name) }
            self.splat = splat
            self.skin = skin
        }
    }

    // Radians each lid swings from open to shut, the upper one doing most of the work.
    private static let lidSwing: (upper: Float, lower: Float) = (0.7, 0.42)

    var pose: Posture
    /// The splat she is drawn with, or where splats can't be drawn the mesh standing in for it once `wear` has it.
    private(set) var entity: Entity?
    let legs: [Leg]
    let spineMid, neck: SIMD3<Float>
    /// Tail bones' heads and directions, root first.
    let tailJoints: [SIMD3<Float>]
    let tailDirections: [SIMD3<Float>]
    let mount: SIMD3<Float>
    private(set) var headPose = Pose()
    private(set) var hipsPose = Pose()

    private let skinner: SplatSkinner?
    private var mesh: CatMeshRig?
    private let boneNames: [String]
    private let joints: [SIMD3<Float>]
    private let eyesCenter: SIMD3<Float>
    private let hips, chest, head, earLeft, earRight: Int
    private let lids: [(upper: Int, lower: Int)]
    private let tail: [Int]

    init(_ files: Files) throws {
        let rig = files.rig
        if let file = files.splat, let skin = files.skin {
            let splat = try SplatLoader.make(file)
            entity = splat.entity
            skinner = try SplatSkinner(splat, skin: skin)
        } else {
            entity = nil
            skinner = nil
        }
        joints = rig.bones.map(\.head)
        boneNames = rig.bones.map(\.name)
        eyesCenter = rig.eyes ?? .zero
        mount = rig.mount ?? .zero

        func bone(_ name: String) throws -> Int {
            guard let index = rig.bones.firstIndex(where: { $0.name == name }) else { throw Failure.missing(name) }
            return index
        }
        hips = try bone("hips")
        chest = try bone("chest")
        head = try bone("head")
        earLeft = try bone("earLeft")
        earRight = try bone("earRight")
        lids = try [("lidLeft", "lidLeftLow"), ("lidRight", "lidRightLow")].map { (try bone($0.0), try bone($0.1)) }
        spineMid = joints[chest]
        neck = joints[head]
        let tail = rig.bones.indices.filter { rig.bones[$0].name.hasPrefix("tail") }
        self.tail = tail
        tailJoints = tail.map { rig.bones[$0].head }
        tailDirections = tail.map { rig.bones[$0].tail - rig.bones[$0].head }
        legs = try Gait.legOrder.filter { name in rig.bones.contains { $0.name == "\(name)Upper" } }.map { name in
            let upper = try bone("\(name)Upper"), lower = try bone("\(name)Lower")
            return Leg(name: name, hip: rig.bones[upper].head, knee: rig.bones[lower].head, paw: rig.bones[lower].tail,
                       fore: rig.bones[upper].parent == "chest", upper: upper, lower: lower)
        }
        pose = Posture(tail: tail.map { _ in TailJoint() }, feet: legs.map(\.paw))
    }

    /// Model-space point between the eyes as posed last frame.
    var eyes: SIMD3<Float> { headPose.apply(eyesCenter) }

    /// Poses every bone; `skinning` off keeps `headPose` and `hipsPose` current without moving the splat or mesh.
    func update(skinning: Bool = true) {
        let p = pose
        var poses = [Pose](repeating: Pose(), count: joints.count)
        var body = Pose.about(spineMid, .x(p.pitch) * .z(p.roll))
        body.t.y += p.lift
        body.t.z += p.back
        let chestPose = Pose.about(spineMid, .x(p.bend / 2)).under(body).under(p.chestMove)
        let hipsPose = Pose.about(spineMid, .y(p.wiggle) * .x(-p.bend / 2)).under(body).under(p.hipsMove)
        var headPose = Pose.about(neck, .y(p.headYaw) * .x(p.headPitch) * .z(p.headRoll))
            .under(chestPose.mix(p.chestMove, p.headSeat))
        headPose.t += p.headShift
        self.headPose = headPose
        self.hipsPose = hipsPose
        poses[chest] = chestPose
        poses[hips] = hipsPose
        poses[head] = headPose
        // An ear swivels its opening out toward its own side, folds back with `earsBack` and flicks outward.
        func ear(_ bone: Int, _ sign: Float, turn: Float, flick: Float) {
            poses[bone] = Pose.about(joints[bone], .y(-sign * turn) * .x(-p.earsBack) * .z(-sign * flick)).under(headPose)
        }
        ear(earLeft, 1, turn: p.earTurnLeft, flick: p.earLeft)
        ear(earRight, -1, turn: p.earTurnRight, flick: p.earRight)
        // The fur above and below an eye swings over it about a hinge behind the eye until the two meet.
        for (lid, shut) in zip(lids, [p.lidLeft, p.lidRight]) {
            poses[lid.upper] = Pose.about(joints[lid.upper], .x(-Self.lidSwing.upper * shut)).under(headPose)
            poses[lid.lower] = Pose.about(joints[lid.upper], .x(Self.lidSwing.lower * shut)).under(headPose)
        }
        // Each tail joint swings sideways about its up axis, lifts, and leans over to one side (+ toward -X).
        var joint = hipsPose
        for (i, bone) in tail.enumerated() {
            let j = p.tail[i]
            joint = Pose.about(joints[bone], .y(j.sway) * .x(-j.lift) * .z(j.lean)).under(joint)
            poses[bone] = joint
        }
        for (i, leg) in legs.enumerated() {
            let parent = leg.fore ? chestPose : hipsPose
            let (a, b, splay) = Gait.solveLeg(hip: leg.hip, knee: leg.knee, paw: leg.paw, target: parent.inverse.apply(p.feet[i]))
            let upper = Pose.about(leg.hip, .z(splay) * .x(a)).under(parent)
            poses[leg.upper] = upper
            poses[leg.lower] = Pose.about(leg.knee, .x(b)).under(upper)
        }
        guard skinning else { return }
        skinner?.run(poses.map(DualQuat.init))
        mesh?.update(poses)
    }

    /// Draws her with `model`, a skinned mesh of this rig's splat (Tools/make_mochi_mesh.py), from now on.
    func wear(_ model: Entity) throws {
        mesh = try CatMeshRig(model, bones: boneNames)
        entity = model
    }
}

/// Mochi as a skinned mesh (Cat.usdz, CatStanding.usdz) where splats can't be drawn, following its rig's bones. The
/// USDZ's joints carry the rig's bone names and rest unrotated, in the splat's model space (Tools/make_mochi_mesh.py).
/// A joint named `<bone>Pivot` turns as its bone does but about its own rest point, carried there by its parent's bone:
/// the mesh's eyelids, which swing about a point behind the eye rather than the lid bone's hinge.
final class CatMeshRig {
    private struct Joint {
        let bone: Int
        let parent: Int?
        let rest: SIMD3<Float>
        let pivot: Bool
    }

    private let model: ModelEntity
    /// In `model.jointNames` order, parents first.
    private let joints: [Joint]

    init(_ entity: Entity, bones: [String]) throws {
        var found = (entity as? ModelEntity).flatMap { $0.jointNames.isEmpty ? nil : $0 }
        entity.forEachDescendant { if found == nil, let m = $0 as? ModelEntity, !m.jointNames.isEmpty { found = m } }
        guard let model = found else { throw CatRig.Failure.missing("skinned model") }
        let paths = model.jointNames
        let restLocal = model.jointTransforms
        var restWorld: [SIMD3<Float>] = []
        joints = try paths.enumerated().map { index, path in
            let parts = path.split(separator: "/")
            let parent = paths.firstIndex(of: parts.dropLast().joined(separator: "/"))
            let name = parts.last.map(String.init) ?? ""
            let pivot = name.hasSuffix("Pivot")
            guard let bone = bones.firstIndex(of: pivot ? String(name.dropLast(5)) : name),
                  parent.map({ $0 < index }) ?? !pivot
            else { throw CatRig.Failure.mismatch(path) }
            restWorld.append(restLocal[index].translation + (parent.map { restWorld[$0] } ?? .zero))
            return Joint(bone: bone, parent: parent, rest: restWorld[index], pivot: pivot)
        }
        self.model = model
    }

    /// `poses`: every bone's motion of model space, in the rig file's order.
    func update(_ poses: [Pose]) {
        // A joint rests unrotated, so posed it sits where its bone's pose takes its rest position, turned by it.
        var world = [Pose](repeating: Pose(), count: joints.count)
        var local = model.jointTransforms
        for (j, joint) in joints.enumerated() {
            let p = poses[joint.bone]
            let carrier = joint.pivot ? joint.parent.map { poses[joints[$0].bone] } ?? p : p
            world[j] = Pose(q: p.q, t: carrier.apply(joint.rest))
            let up = joint.parent.map { world[$0] } ?? Pose()
            local[j].rotation = up.q.inverse * world[j].q
            local[j].translation = up.q.inverse.act(world[j].t - up.t)
        }
        model.jointTransforms = local
    }
}

/// A bone's motion as a unit dual quaternion, which blends without the volume loss of blended matrices.
nonisolated struct DualQuat {
    let real: SIMD4<Float>
    let dual: SIMD4<Float>

    init(_ pose: Pose) {
        real = pose.q.vector
        dual = 0.5 * (simd_quatf(ix: pose.t.x, iy: pose.t.y, iz: pose.t.z, r: 0) * pose.q).vector
    }
}

/// Skins a splat on the GPU each frame: a compute pass writes all of the buffer RealityKit draws it from, which
/// RealityKit reads once the pass is done.
final class SplatSkinner {
    enum Failure: Error {
        case noGPU
    }

    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private let rest: any MTLBuffer
    private let skin: any MTLBuffer
    private let target: (any MTLCommandBuffer) -> any MTLBuffer
    private var count: UInt32
    /// The bones the splats were last skinned to.
    private var skinned: [DualQuat] = []
    /// How far a bone's quaternions may drift from `skinned` before a pass is worth rewriting every splat; well under a
    /// pixel on the cat's 30 cm.
    private static let drift: Float = 2e-4

    /// Passes run and skipped, and the GPU time of the last pass, for perf runs.
    nonisolated struct Stats {
        var passes = 0
        var skipped = 0
        var milliseconds = 0.0
    }
    nonisolated static let stats = Mutex(Stats())

    /// One device, queue and compiled pipeline for every skinner.
    private static let gpu: (device: any MTLDevice, queue: any MTLCommandQueue, pipeline: any MTLComputePipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "skinSplats"),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else { return nil }
        return (device, queue, pipeline)
    }()

    init(_ splat: Splat, skin: [UInt8]) throws {
        guard let gpu = Self.gpu,
              let rest = splat.rest.withUnsafeBytes({ gpu.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }),
              let skin = gpu.device.makeBuffer(bytes: skin, length: skin.count)
        else { throw Failure.noGPU }
        queue = gpu.queue
        pipeline = gpu.pipeline
        self.rest = rest
        self.skin = skin
        target = splat.replace
        count = UInt32(splat.count)
    }

    /// `bones` in skin order, at most a few hundred.
    func run(_ bones: [DualQuat]) {
        if bones.count == skinned.count, zip(bones, skinned).allSatisfy({ a, b in
            max(simd_abs(a.real - b.real).max(), simd_abs(a.dual - b.dual).max()) < Self.drift
        }) {
            Self.stats.withLock { $0.skipped += 1 }
            return
        }
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(rest, offset: 0, index: 0)
        encoder.setBuffer(skin, offset: 0, index: 1)
        bones.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 2) }
        encoder.setBuffer(target(commands), offset: 0, index: 3)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 4)
        let group = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        encoder.dispatchThreads(MTLSize(width: Int(count), height: 1, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        commands.addCompletedHandler { done in
            let milliseconds = (done.gpuEndTime - done.gpuStartTime) * 1000
            SplatSkinner.stats.withLock { $0.passes += 1; $0.milliseconds = milliseconds }
        }
        commands.commit()
        skinned = bones
    }
}
