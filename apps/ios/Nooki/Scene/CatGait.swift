import Foundation
import simd

/// Where the body stands in the room: `at` its origin and `yaw` about +Y, `scale` room units per model unit, and
/// `velocity` (room units/s) and `yawRate` (rad/s) to tell where it will be a moment later.
struct BodyFrame {
    var at = SIMD3<Float>.zero
    var yaw: Float = 0
    var scale: Float = 1
    var velocity = SIMD3<Float>.zero
    var yawRate: Float = 0

    func toRoom(_ p: SIMD3<Float>) -> SIMD3<Float> { simd_quatf.y(yaw).act(p * scale) + at }
    func toModel(_ p: SIMD3<Float>) -> SIMD3<Float> { simd_quatf.y(-yaw).act(p - at) / scale }

    func ahead(_ seconds: Float) -> BodyFrame {
        var f = self
        f.at += velocity * seconds
        f.yaw += yawRate * seconds
        return f
    }
}

private func wrap(_ a: Float) -> Float { atan2(sin(a), cos(a)) }

/// How a cat's body moves, independent of any one splat, ported from nooki-scene/src/three/catGait.js: a two-bone leg
/// solver and a walk that keeps each paw where it was set down. Model space: front toward -Z, up +Y, paws on y = 0.
///
/// A paw in stance holds its spot in the room whatever the body does, and a swing carries it to where its stance spot
/// will be halfway through its next stance. Walking, that spot is halfway from the rest paw to under the hip, so the
/// stride stays within the leg's reach. The cycle runs slower at a slow walk and stops once every paw has stepped back
/// to its rest spot.
final class Gait {
    // A walk: each paw on the ground for 60% of the cycle, set down in the order left hind, left fore, right hind,
    // right fore, a quarter cycle apart.
    static let legOrder = ["leftHind", "leftFore", "rightHind", "rightFore"]
    private static let duty: Float = 0.6
    private static let phaseOffset: [String: Float] = ["leftHind": 0, "leftFore": 0.25, "rightHind": 0.5, "rightFore": 0.75]

    private struct Leg {
        let offset: Float
        let rest: SIMD3<Float>
        let stride: SIMD3<Float>
        var anchor: SIMD3<Float>?
        var from = SIMD3<Float>.zero
        var swinging = false
        var done = true
    }

    /// 0 standing, 1 walking; eased so the body's rocking starts and stops softly.
    private(set) var amount: Float = 0
    private var phase: Float = 0
    private var period: Float
    private let basePeriod: Float
    private let speed: Float
    private let lift: Float
    private var legs: [Leg]
    private var frame = BodyFrame()
    private var moving = false

    /// `legs` in the rig's order; `speed` (model units/s) is where the cycle takes `period`.
    init(_ legs: [CatRig.Leg], period: Float = 0.55, speed: Float = 0.26, lift: Float = 0.022) {
        basePeriod = period
        self.period = period
        self.speed = speed
        self.lift = lift
        self.legs = legs.map {
            var stride = $0.paw
            stride.z = ($0.paw.z + $0.hip.z) / 2
            return Leg(offset: Self.phaseOffset[$0.name] ?? 0, rest: $0.paw, stride: stride)
        }
    }

    /// Bends a leg so its paw reaches `target`. `hip`, `knee` and `paw` are the rest joints in the leg's parent frame,
    /// `target` is in that frame too. The leg swings out about +Z at the hip to the target's side, then bends in its rest
    /// plane, folding the way it does at rest (back for a cat's elbow, forward for the knee). Returns the upper bone's
    /// turn about the hip and the lower bone's about the knee relative to the upper, both about +X, and the swing out.
    static func solveLeg(hip: SIMD3<Float>, knee: SIMD3<Float>, paw: SIMD3<Float>,
                         target: SIMD3<Float>) -> (Float, Float, Float) {
        // Angles in the side (y, z) plane as a turn about +X sees them, and in the front (x, y) plane as a turn about +Z
        // swings a leg hanging down.
        func side(_ y: Float, _ z: Float) -> Float { atan2(z, y) }
        func front(_ x: Float, _ y: Float) -> Float { atan2(x, -y) }
        let splay = wrap(front(target.x - hip.x, target.y - hip.y) - front(paw.x - hip.x, paw.y - hip.y))
        let foot = simd_quatf.z(-splay).act(target - hip) + hip
        let upper = hypot(knee.y - hip.y, knee.z - hip.z)
        let lower = hypot(paw.y - knee.y, paw.z - knee.z)
        let dy = foot.y - hip.y, dz = foot.z - hip.z
        let reach = min(max(hypot(dy, dz), abs(upper - lower) + 1e-4), upper + lower - 1e-4)
        let opening = acos(min(max((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1), 1))
        let restUpper = side(knee.y - hip.y, knee.z - hip.z)
        let s = sin(restUpper - side(paw.y - hip.y, paw.z - hip.z))
        let bend: Float = s > 0 ? 1 : s < 0 ? -1 : 1
        let upperAngle = side(dy, dz) + bend * opening
        let kneeY = hip.y + upper * cos(upperAngle)
        let kneeZ = hip.z + upper * sin(upperAngle)
        let lowerAngle = side(foot.y - kneeY, foot.z - kneeZ)
        let restLower = side(paw.y - knee.y, paw.z - knee.z)
        // Wrapped, since legs point straight down where the angle crosses ±π.
        let turnUpper = wrap(upperAngle - restUpper)
        return (turnUpper, wrap(lowerAngle - restLower - turnUpper), splay)
    }

    /// Advances the cycle and the paws. `stepping` keeps the paws moving even without ground speed (turning on the
    /// spot); without `planted` the paws ride with the body (in the air) and are set down again where they are.
    func update(_ dt: Float, _ frame: BodyFrame, stepping: Bool, planted: Bool) {
        let pace = max(simd_length(frame.velocity) / frame.scale, abs(frame.yawRate) * 0.12)
        let moving = planted && (stepping || pace > 1e-3)
        for i in legs.indices {
            if !planted || legs[i].anchor == nil {
                legs[i].anchor = frame.toRoom(legs[i].rest)
                legs[i].swinging = false
                legs[i].done = true
            } else if moving {
                legs[i].done = false
            } else if !legs[i].swinging && !legs[i].done, let anchor = legs[i].anchor {
                // Coming to a stop: a paw already under the body stays; the others take one more step.
                legs[i].done = simd_distance(frame.toModel(anchor), legs[i].rest) < 0.004
            }
        }
        let active = legs.contains { !$0.done }
        amount += ((moving ? 1 : 0) - amount) * (1 - exp(-dt * 6))
        period = basePeriod * min(max(sqrt(speed / max(pace, 1e-3)), 1), 1.6)
        if active { phase = (phase + dt / period).truncatingRemainder(dividingBy: 1) }
        self.frame = frame
        self.moving = moving

        for i in legs.indices where !legs[i].done {
            let u = (phase + legs[i].offset).truncatingRemainder(dividingBy: 1)
            if u >= Self.duty && !legs[i].swinging {
                legs[i].swinging = true
                legs[i].from = legs[i].anchor ?? .zero
            } else if u < Self.duty && legs[i].swinging {
                legs[i].swinging = false
                legs[i].anchor = touchdown(legs[i], 1)
                if !moving { legs[i].done = true }
            }
        }
    }

    /// Where a swinging paw lands, `w` of the way through its swing; once stopping, back at its rest spot.
    private func touchdown(_ leg: Leg, _ w: Float) -> SIMD3<Float> {
        let swing = (1 - Self.duty) * period
        return frame.ahead((1 - w) * swing + Self.duty * period / 2).toRoom(moving ? leg.stride : leg.rest)
    }

    /// Paw position in model space, for the leg at `index` in the rig's order.
    func foot(_ index: Int) -> SIMD3<Float> {
        let leg = legs[index]
        guard leg.swinging else { return frame.toModel(leg.anchor ?? frame.toRoom(leg.rest)) }
        let u = (phase + leg.offset).truncatingRemainder(dividingBy: 1)
        let w = (u - Self.duty) / (1 - Self.duty)
        let target = touchdown(leg, w)
        let step = simd_distance(leg.from, target) / frame.scale
        var out = frame.toModel(simd_mix(leg.from, target, SIMD3(repeating: w * w * (3 - 2 * w))))
        // A short settling step barely clears the floor.
        out.y += lift * min(1, 0.3 + step / 0.03) * sin(w * .pi)
        return out
    }

    /// The body walks a little low and dips as each paw takes its weight, twice per side per cycle, rocks nose down as
    /// the weight passes to the fore paws, and rolls toward the planted side.
    func body() -> (y: Float, pitch: Float, roll: Float) {
        let a = phase * .pi * 2
        let m = amount
        return (-m * (0.012 + 0.004 * (1 - cos(2 * a)) * 0.5), 0.012 * m * sin(2 * a), 0.025 * m * sin(a))
    }
}

/// The tail as a chain of damped springs on top of whatever the motion poses: the body's accelerations push each
/// joint off its posed angle, and each is pulled back toward its parent's swing, so the tip lags most and overshoots
/// last. `bones` are the joints' rest directions in model space.
final class TailSpring {
    struct Joint {
        let dir: SIMD3<Float>
        let k, c: Float
        var lean: Float = 0, leanSpeed: Float = 0, lift: Float = 0, liftSpeed: Float = 0
    }

    private(set) var joints: [Joint]
    private let gain: Float = 3
    private let limit: Float = 0.7

    init(_ bones: [SIMD3<Float>], frequency: [Float] = [11, 8, 6], damping: Float = 0.3) {
        joints = bones.enumerated().map { i, dir in
            let f = frequency[min(i, frequency.count - 1)]
            return Joint(dir: simd_normalize(dir), k: f * f, c: 2 * damping * f)
        }
    }

    /// `force` is the inertial push on the tail per unit mass, model units/s² in the body's frame: minus its
    /// acceleration.
    func update(_ dt: Float, _ force: SIMD3<Float>) {
        let steps = max(Int(ceil(dt * 240)), 1)
        let h = dt / Float(steps)
        for _ in 0..<steps {
            var parent = (lean: Float(0), leanSpeed: Float(0), lift: Float(0), liftSpeed: Float(0))
            for i in joints.indices {
                var j = joints[i]
                // Torques of the push on the bone, about +Z for leaning and about -X for lifting.
                let leanTorque = j.dir.x * force.y - j.dir.y * force.x
                let liftTorque = j.dir.z * force.y - j.dir.y * force.z
                let lean = j.k * (j.lean - parent.lean) + j.c * (j.leanSpeed - parent.leanSpeed)
                let lift = j.k * (j.lift - parent.lift) + j.c * (j.liftSpeed - parent.liftSpeed)
                j.leanSpeed += h * (gain * leanTorque - lean)
                j.liftSpeed += h * (gain * liftTorque - lift)
                j.lean = min(max(j.lean + h * j.leanSpeed, -limit), limit)
                j.lift = min(max(j.lift + h * j.liftSpeed, -limit), limit)
                joints[i] = j
                parent = (j.lean, j.leanSpeed, j.lift, j.liftSpeed)
            }
        }
    }
}
