import Foundation
import Pet
import RealityKit
import simd

private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
private func ease(_ t: Float) -> Float { t * t * (3 - 2 * t) }
private func shortest(_ a: Float, _ b: Float) -> Float { a + atan2(sin(b - a), cos(b - a)) }
private func facing(_ dx: Float, _ dz: Float) -> Float { atan2(-dx, -dz) }

// Model units the chest and the hips move at a full breath in.
private let breathChest = SIMD3<Float>(0, 0.0014, -0.0005)
private let breathHips = SIMD3<Float>(0, 0.0003, 0)

/// Her breathing, one breath at a time, each a little longer or deeper than the last: about 0.4 a second, slower and
/// deeper when drowsy, quicker and deeper after exertion. `value` is how far in she has breathed, about 0 to 1.
private struct Breath {
    var phase = Float.random(in: 0..<1)
    var value: Float = 0
    var length = Float.random(in: 0.85..<1.2)
    var depth = Float.random(in: 0.75..<1.15)

    /// `drowse` and `effort` run from 0 to 1.
    mutating func update(_ dt: Float, drowse: Float, effort: Float) {
        phase += dt * 0.4 * (1 - 0.35 * drowse) * (1 + 0.7 * effort) / length
        if phase >= 1 {
            phase = phase.truncatingRemainder(dividingBy: 1)
            length = .random(in: 0.85..<1.2)
            depth = .random(in: 0.75..<1.15)
        }
        // In over the first 40% of a breath, out over the next 45%, then a pause.
        let u = phase
        let shape = u < 0.4 ? ease(u / 0.4) : u < 0.85 ? 1 - ease((u - 0.4) / 0.45) : 0
        value = shape * depth * (1 + 0.5 * drowse) * (1 + 0.4 * effort)
    }
}

/// How far she lies down: `loaf` lowers her onto her folded legs with the tail along the floor, `curl` then tucks her
/// head down and shuts her eyes for sleep. Each follows its target as a critically damped spring, so it eases in and
/// out without overshoot and turns smoothly when the target changes halfway.
struct Lying {
    var loaf: Float = 0, curl: Float = 0
    private var loafSpeed: Float = 0, curlSpeed: Float = 0
    // Per second; a change takes about 5 / rate seconds to settle.
    static let rate: Float = 2.4

    static func target(_ pose: NookiRestPose) -> (loaf: Float, curl: Float) {
        switch pose {
        case .sit: (0, 0)
        case .loaf: (1, 0)
        case .sleep: (1, 1)
        }
    }

    mutating func update(_ dt: Float, toward pose: NookiRestPose) {
        let goal = Self.target(pose)
        let steps = max(Int(ceil(dt * 120)), 1)
        let h = dt / Float(steps), w = Self.rate
        for _ in 0..<steps {
            loafSpeed += h * (w * w * (goal.loaf - loaf) - 2 * w * loafSpeed)
            curlSpeed += h * (w * w * (goal.curl - curl) - 2 * w * curlSpeed)
            loaf += h * loafSpeed
            curl += h * curlSpeed
        }
    }

    /// Eases from where she lies to sitting up, `u` from 0 to 1 of the way; `from` is where she was at `u` = 0.
    mutating func rise(from: Lying, _ u: Float) {
        let k = 1 - ease(u)
        loaf = from.loaf * k
        curl = from.curl * k
        loafSpeed = 0
        curlSpeed = 0
    }

    var isDown: Bool { loaf > 0.002 || curl > 0.002 }
}

/// Mochi on her one skeleton and splat, ported from nooki-scene/src/three/catWalker.js and catSeat.js. Sitting she
/// looks around, twitches her ears and waves her tail, and lies down in a loaf or asleep with her chin tucked; given a
/// route she gets up, walks and jumps along its waypoints, and sits down at the other end. Every pose is the same splat
/// bent by the rig, so she keeps her size, shape and coat whatever she does.
final class CatWalker {
    struct Waypoint {
        enum Move { case walk, jump }
        var at: SIMD3<Float>
        /// How she gets to this point from the one before.
        var move: Move = .walk
    }

    /// Somewhere she can go from her resting spot and sit for a while: `path` leads there from it, each waypoint
    /// reached by its `move`, `rest` is her yaw once there, and `arrive` runs as she lands on the last one.
    struct Destination {
        let id: String
        var path: [Waypoint]
        var rest: Float
        /// A couple of paw pats on whatever she landed on, before she sits.
        var play = false
        var arrive: (() -> Void)?
    }

    /// Body postures as rig values; feet are offsets (up, back) from the rest paws in model units, `tail` lifts each
    /// tail joint (negative lowers it), `sway` swings it to her left and `lean` rolls it over; `shut` closes the lids,
    /// `neck` moves the head in model units.
    private struct Posture {
        var lift: Float = 0, back: Float = 0, pitch: Float = 0, bend: Float = 0, headPitch: Float = 0, seat: Float = 0
        var headYaw: Float = 0, headRoll: Float = 0, shut: Float = 0
        var neck = SIMD3<Float>.zero
        var fore = SIMD2<Float>.zero, hind = SIMD2<Float>.zero
        var tail: [Float] = [0, 0, 0]
        var sway: [Float] = [0, 0, 0]
        var lean: [Float] = [0, 0, 0]

        static let stand = Posture()
        // As a cat sits seen side on: chest up on straight fore legs under the shoulders, the back rounded so the rump
        // sits upright on the floor over the folded hind legs, the head level over the chest, and the tail on the floor
        // along her left side toward the fore paws.
        static let sit = Posture(lift: -0.008, back: -0.05, pitch: 0.7, bend: -0.5, seat: 1, neck: [0, 0.017, -0.011],
                                 fore: [0, 0.02], hind: [0, -0.09], tail: [-1.07, -0.79, -0.79], sway: [1.12, -0.42, -1.12],
                                 lean: [-1.32, -0.31, -0.05])
        // The loaf: belly down, back rounded, fore paws tucked under the chest, the tail along her left side.
        static let loaf = Posture(lift: -0.05, bend: -0.3, neck: [0, -0.008, 0.01], fore: [0, 0.08], hind: [0, -0.09],
                                  tail: [-1.7, -0.09, -0.12], sway: [0.6, -0.67, -0.42], lean: [-0.37, -0.91, -0.56])
        // Asleep in the loaf: the head sinks and the chin drops toward the chest, turned a little toward the tail,
        // eyes shut.
        static let sleep = Posture(lift: -0.05, bend: -0.3, headPitch: -0.3, headYaw: -0.15, headRoll: -0.06, shut: 1,
                                   neck: [0, -0.02, 0.006], fore: [0, 0.08], hind: [0, -0.09], tail: [-1.7, -0.09, -0.12],
                                   sway: [0.6, -0.67, -0.42], lean: [-0.37, -0.91, -0.56])

        static func lying(_ lying: Lying) -> Posture { blend(blend(.sit, .loaf, lying.loaf), .sleep, lying.curl) }

        static func blend(_ a: Posture, _ b: Posture, _ t: Float) -> Posture {
            Posture(lift: lerp(a.lift, b.lift, t), back: lerp(a.back, b.back, t), pitch: lerp(a.pitch, b.pitch, t),
                    bend: lerp(a.bend, b.bend, t), headPitch: lerp(a.headPitch, b.headPitch, t), seat: lerp(a.seat, b.seat, t),
                    headYaw: lerp(a.headYaw, b.headYaw, t),
                    headRoll: lerp(a.headRoll, b.headRoll, t), shut: lerp(a.shut, b.shut, t),
                    neck: simd_mix(a.neck, b.neck, SIMD3(repeating: t)),
                    fore: simd_mix(a.fore, b.fore, SIMD2(repeating: t)), hind: simd_mix(a.hind, b.hind, SIMD2(repeating: t)),
                    tail: zip(a.tail, b.tail).map { lerp($0, $1, t) },
                    sway: zip(a.sway, b.sway).map { lerp($0, $1, t) },
                    lean: zip(a.lean, b.lean).map { lerp($0, $1, t) })
        }
    }

    private struct Step {
        let duration: Float
        let run: (_ u: Float) -> Void
        var time: Float = 0
    }

    // Room units per second.
    private let walkSpeed: Float = 0.14
    // Seconds she takes to reach that speed from standing, and to stop from it: about one stride.
    private let rampTime: Float = 0.6
    // Seconds the head takes to follow the body's bob, pitch and roll while walking.
    private let headLag: Float = 0.3

    let behavior: CatBehavior
    /// Plans a trip on her own every now and then; off, she waits for `trip()`.
    var wandering: Bool
    /// Set when a brain sends her about and says when she rests: she neither wanders, comes home nor lies down on
    /// her own.
    var directed = false {
        didSet { behavior.directed = directed }
    }
    /// The body the brain has her rest in, eased into by `lying`; `sit` whenever she is on the move.
    private(set) var rest = NookiRestPose.sit
    private(set) var lying = Lying()
    let rig: CatRig
    /// Where she sits from the splat's origin, in model units: rooms place her sitting body by this point.
    static let seat = SIMD3<Float>(0.01, 0, -0.058)

    private let group: Entity
    private let scale: Float
    private let gait: Gait
    private let tailSpring: TailSpring
    /// Where she rests between outings, facing `homeYaw`.
    private let home: SIMD3<Float>
    private let homeYaw: Float
    /// The route's far end, where `trip()` takes her.
    let main: Destination?
    /// Where she is sitting now, nil at home.
    private var away: Destination?
    private var yaw: Float
    private var planYaw: Float = 0
    private var steps: [Step] = []
    private var wait: Float
    private var time: Float = 0
    private var posture = Posture.sit
    private var resting: Float = 1
    private var lookPitch: Float = 0
    private var gaze: Float = 0
    private var stepping = false
    private var free = false
    private var wiggle: Float = 0
    private var tread = SIMD2<Float>.zero
    private var frame: BodyFrame
    private var last: (at: SIMD3<Float>, yaw: Float)
    private var steady: (y: Float, pitch: Float, roll: Float) = (0, 0, 0)
    private var tailTrack: [(at: SIMD3<Float>, dt: Float)] = []
    private var tailPush = SIMD3<Float>.zero
    private var breath = Breath()
    private var effort: Float = 0
    private var viewer: SIMD3<Float>?
    /// Where her spine bends sitting, and the floor under it, in model space.
    private let spine: SIMD3<Float>
    private let floor: SIMD3<Float>

    /// `group` is what she moves and turns, `scale` turns model units into room units. She starts sitting at the
    /// route's end (or at `group` without a route) facing `rests[1]`; a route runs from the first resting spot to the
    /// second, `rests` being her yaws at those two spots.
    init(group: Entity, rig: CatRig, scale: Float, rests: [Float], route: [Waypoint] = [], wandering: Bool) {
        self.group = group
        self.rig = rig
        self.scale = scale
        self.wandering = wandering
        behavior = CatBehavior(tailJoints: rig.pose.tail.count)
        gait = Gait(rig.legs, speed: walkSpeed / scale)
        tailSpring = TailSpring(rig.tailDirections)
        yaw = rests[rests.count - 1]
        homeYaw = yaw
        if let end = route.last { group.position = end.at }
        home = group.position
        // The route runs from the far end home; the way out is the same points backwards, each reached the way the
        // one after it was.
        let out = Array(route.reversed())
        main = route.count > 1 ? Destination(id: "main", path: (1..<out.count).map { Waypoint(at: out[$0].at, move: out[$0 - 1].move) },
                                             rest: rests[0]) : nil
        frame = BodyFrame(at: group.position, yaw: yaw, scale: scale)
        last = (group.position, yaw)
        spine = rig.spineMid + [0, Posture.sit.lift, Posture.sit.back]
        floor = [spine.x, 0, spine.z]
        wait = Float.random(in: 6..<12)
    }

    var moving: Bool { !steps.isEmpty }
    var canTrip: Bool { main != nil }
    /// The destination she is at or on her way to, nil at home.
    var place: String? { away?.id }
    /// Her heading in the room, 0 facing -z.
    var heading: Float { yaw }
    /// Where she stands in the room.
    var at: SIMD3<Float> { group.position }

    func pet() {
        behavior.pet()
    }

    /// Rests her in `pose`, lying down or sitting up. Only while she is still.
    func settle(_ pose: NookiRestPose) {
        guard !moving else { return }
        rest = pose
    }

    /// Gets up for a couple of paw pats on what she is on, and sits again.
    func pats() {
        guard !moving else { return }
        rest = .sit
        standUp()
        pat()
        sitDown()
    }

    /// Gets up and drops into a low crouch, rump up and wiggling, and sits again.
    func crouch() {
        guard !moving else { return }
        rest = .sit
        standUp()
        var low = Posture.stand
        low.lift = -0.02
        low.pitch = -0.3
        low.bend = 0.05
        low.headPitch = 0.3
        low.fore = [0, -0.03]
        low.tail = [0.4, 0.2, 0.1]
        add(1.8) { [unowned self] u in
            let t = u * 1.8
            keyframes([(0, .stand), (0.35, low), (1.45, low), (1.8, .stand)], t)
            if t > 0.35 && t < 1.45 { posture.lift += 0.0025 * sin(t * 26) }
        }
        sitDown()
    }

    /// Gets up for one quick hop forward onto the fore paws, and sits again.
    func hop() {
        guard !moving else { return }
        rest = .sit
        standUp()
        var air = Posture.stand
        air.lift = 0.035
        air.pitch = 0.3
        air.headPitch = 0.1
        air.fore = [0.04, -0.03]
        air.tail = [0.5, 0.3, 0.1]
        add(0.7) { [unowned self] u in
            keyframes([(0, .stand), (0.25, air), (0.5, .stand), (0.7, .stand)], u * 0.7)
        }
        sitDown()
    }

    /// Gets up and turns a full circle on the spot after her tail, and sits again facing as before.
    func spin() {
        guard !moving else { return }
        rest = .sit
        standUp()
        planYaw = yaw
        let home = yaw
        for third in 1...3 { turn(home + Float(third) * 2 * .pi / 3) }
        turn(home)
        sitDown()
    }

    /// Model-space point she sees whoever watches her from.
    func watch(_ point: SIMD3<Float>) {
        viewer = point
        behavior.watch(point)
    }

    /// Looks toward a finger `offset` from her head on screen, in about -1 to 1 across it, x right and y down; nil
    /// once it lifts. The point lies in front of her eyes, toward the camera, shifted across the camera's view.
    func follow(_ offset: SIMD2<Float>?) {
        guard let offset, let viewer else { return behavior.lookAt(nil) }
        let back = simd_normalize(viewer - eyes)
        let right = simd_normalize(simd_cross([0, 1, 0], back))
        let up = simd_cross(back, right)
        behavior.lookAt(eyes + 0.3 * (back + right * offset.x - up * offset.y))
    }

    /// Sets off to the route's other end now, or back home from wherever she is; `stretch` forces the stretch first.
    func trip(stretch: Bool = false) {
        guard let main else { return }
        go(to: away == nil ? main : nil, stretch: stretch)
    }

    /// Takes her to `destination`, or home with nil. From one destination to another she only climbs down to the
    /// floor and crosses it, instead of going back to her resting spot first.
    func go(to destination: Destination?, stretch: Bool = false) {
        guard !moving, destination?.id != away?.id else { return }
        planYaw = yaw
        behavior.stir(0.2)
        rest = .sit
        standUp()
        if stretch { self.stretch() }
        let points = [Waypoint(at: home)] + (away?.path ?? [])
        if let destination, away != nil, let exit = floorExit(points), let entry = floorEntry(destination.path) {
            retrace(points, downTo: exit)
            var from = points[exit].at
            for corner in detour(from, destination.path[entry].at) + [destination.path[entry].at] {
                leg(from, corner, .walk)
                from = corner
            }
            follow(destination, from: entry + 1, at: from)
        } else {
            retrace(points, downTo: 0)
            if let destination { follow(destination, from: 0, at: home) }
        }
        turn(destination?.rest ?? homeYaw)
        sitDown()
        away = destination
    }

    /// Height below which a waypoint counts as standing on the floor.
    var floorTop: Float = 0.04
    /// A round obstacle on the floor, center and radius in the floor plane, that walks between destinations go around.
    var keepOut: (center: SIMD2<Float>, radius: Float)?

    /// Back along the way she came, each leg crossed the way it was reached, until she stands on `points[index]`.
    private func retrace(_ points: [Waypoint], downTo index: Int) {
        for i in stride(from: points.count - 1, to: index, by: -1) { leg(points[i].at, points[i - 1].at, points[i].move) }
    }

    private func follow(_ destination: Destination, from index: Int, at start: SIMD3<Float>) {
        var from = start
        for point in destination.path[index...] {
            leg(from, point.at, point.move)
            from = point.at
        }
        if let arrive = destination.arrive { add(0.01) { _ in arrive() } }
        if destination.play { pat() }
    }

    /// The last floor point on the way out to where she is: as far as she needs to come back.
    private func floorExit(_ points: [Waypoint]) -> Int? {
        points.indices.dropFirst().last { points[$0].at.y < floorTop }
    }

    /// The floor point a destination's path is joined at: the one its last jump takes off from, else its first.
    private func floorEntry(_ path: [Waypoint]) -> Int? {
        let takeoff = path.indices.dropLast().last { path[$0].at.y < floorTop && path[$0 + 1].move == .jump }
        return takeoff ?? (path.first.map { $0.at.y < floorTop } == true ? 0 : nil)
    }

    /// Corners around `keepOut` when the straight walk from `a` to `b` would cross it, always on its front (+z)
    /// side, where the floor is open; each new leg is checked again once.
    private func detour(_ a: SIMD3<Float>, _ b: SIMD3<Float>, depth: Int = 2) -> [SIMD3<Float>] {
        guard let keepOut, depth > 0 else { return [] }
        let a2 = SIMD2(a.x, a.z), d = SIMD2(b.x, b.z) - a2
        let t = simd_clamp(simd_dot(keepOut.center - a2, d) / max(simd_length_squared(d), 1e-6), 0, 1)
        var side = a2 + t * d - keepOut.center
        guard simd_length(side) < keepOut.radius else { return [] }
        if side.y < 0 || simd_length(side) < 1e-4 { side.y = abs(side.y) + 0.05 }
        let flat = keepOut.center + simd_normalize(side) * keepOut.radius * 1.45
        let corner = SIMD3(flat.x, a.y, flat.y)
        return detour(a, corner, depth: depth - 1) + [corner] + detour(corner, b, depth: depth - 1)
    }

    func update(_ dt: Float) {
        time += dt
        // Wandering she sets off now and then; otherwise she still comes home from wherever she was sent.
        if !directed, !moving, wandering && canTrip || away != nil {
            wait -= dt
            if wait <= 0 {
                if wandering { trip(stretch: Float.random(in: 0..<1) < 0.6) } else { go(to: nil) }
            }
        }
        stepping = false
        free = false
        gaze = 0
        if !steps.isEmpty {
            steps[0].time += dt
            let step = steps[0]
            let u = min(step.time / step.duration, 1)
            step.run(u)
            if u >= 1 { steps.removeFirst() }
            if steps.isEmpty { wait = Float.random(in: 10..<22) * lerp(1.6, 0.6, behavior.mood.energy) }
        }
        // Tired she lies down to doze, and gets up again once rested.
        if !directed && !moving && rest == .sit && behavior.drowse > 0.7 && behavior.mood.energy < 0.3 { rest = .loaf }
        else if !directed && !moving && rest != .sit && behavior.mood.energy > 0.5 { rest = .sit }
        // On the move `rest` is `sit`, and standing up has already brought her up off the floor.
        if !moving {
            lying.update(dt, toward: rest)
            posture = .lying(lying)
        }
        behavior.napping = rest != .sit
        // Walking winds her a little, jumping more; resting she gets her breath back over half a minute or so.
        let winding: Float = free ? 0.6 : stepping ? 0.1 : 0
        effort = winding > 0 ? min(1, effort + winding * dt) : effort * exp(-dt / 12)
        group.orientation = .y(yaw)
        if dt > 0 {
            frame.velocity = (group.position - last.at) / dt
            frame.yawRate = (yaw - last.yaw) / dt
        }
        frame.at = group.position
        frame.yaw = yaw
        last = (group.position, yaw)
        behavior.update(dt, eyes: eyes)
        resting += ((moving ? 0 : 1) - resting) * (1 - exp(-dt * 4))
        pose(dt)
    }

    /// Model-space point between her eyes, as posed last frame.
    var eyes: SIMD3<Float> { rig.eyes }

    /// Shows her; the rig is shared with other rooms' walkers.
    func show() {
        rig.entity?.isEnabled = true
    }

    /// Writes the posture, gait, and the resting behavior as far as she is at rest, into the rig.
    private func pose(_ dt: Float) {
        gait.update(dt, frame, stepping: stepping, planted: !free)
        let g = gait.body()
        let s = posture
        let b = behavior.state
        let r = resting
        // Lying she holds her head and tail stiller, and asleep barely follows what she looks at.
        let calm = 1 - 0.5 * lying.loaf - 0.3 * lying.curl
        let still = 1 - 0.7 * lying.curl
        var p = rig.pose
        p.lift = s.lift + g.y
        p.back = s.back
        p.pitch = s.pitch + g.pitch
        p.roll = g.roll
        p.bend = s.bend
        p.wiggle = wiggle
        p.headSeat = s.seat
        // Walking she watches the floor ahead.
        lookPitch += (gaze - lookPitch) * (1 - exp(-dt * 4))
        p.headPitch = s.headPitch + lerp(lookPitch, b.pitch, r) * still
        p.headYaw = s.headYaw + lerp(0.12 * noise(time * 0.5, 8), b.yaw, r) * still
        p.headRoll = s.headRoll + b.roll * r * still
        steadyHead(&p, dt, g)
        p.headShift += s.neck
        settle(&p, dt, r)
        p.earLeft = b.earLeft * r
        p.earRight = b.earRight * r
        p.earsBack = b.earsBack * r
        // On the move the ears point ahead; the eyes blink whatever she does, but droop only at rest.
        p.earTurnLeft = lerp(-0.1, b.earTurnLeft, r)
        p.earTurnRight = lerp(-0.1, b.earTurnRight, r)
        p.lidLeft = max(behavior.blink, b.lidLeft * r, s.shut)
        p.lidRight = max(behavior.blink, b.lidRight * r, s.shut)
        for (i, leg) in rig.legs.enumerated() {
            let offset = leg.fore ? s.fore : s.hind
            var foot = gait.foot(i)
            foot.y += offset.x + (leg.name == "leftHind" ? tread.x : leg.name == "rightHind" ? tread.y : 0)
            foot.z += offset.y
            p.feet[i] = foot
        }
        // The tail rides high on the move and waves slowly, each joint a little later than the one before; on top of
        // that it swings with the body's turns, starts and landings.
        tailSpring.update(dt, tailPush)
        for i in p.tail.indices {
            let spring = tailSpring.joints[min(i, tailSpring.joints.count - 1)]
            let fi = Float(i)
            let k = min(i, s.tail.count - 1)
            p.tail[i].sway = s.sway[k] + lerp((0.06 + 0.05 * fi) * sin(time * 1.6 - fi * 0.8), b.tailSway[i] * calm, r)
            p.tail[i].lift = s.tail[k] + 0.1 * gait.amount + b.tailLift[i] * r * calm + spring.lift
            p.tail[i].lean = s.lean[k] + spring.lean
        }
        rig.pose = p
        rig.update()
        tailPush = tailForce(dt)
    }

    /// Minus the acceleration of the tail's root over the last frames, in model units and axes.
    private func tailForce(_ dt: Float) -> SIMD3<Float> {
        guard let base = rig.tailJoints.first else { return .zero }
        let local = simd_quatf.y(yaw).act(rig.hipsPose.apply(base) * scale) + group.position
        tailTrack.append((local, dt))
        if tailTrack.count > 3 { tailTrack.removeFirst() }
        guard tailTrack.count == 3, dt > 0 else { return .zero }
        let (a, b, c) = (tailTrack[0], tailTrack[1], tailTrack[2])
        let v1 = (b.at - a.at) / b.dt
        let v2 = (c.at - b.at) / c.dt
        let force = simd_quatf.y(-yaw).act((v1 - v2) / ((b.dt + c.dt) / 2)) / scale
        // A cut in the motion (a teleport, a long hitch) is not a push.
        return simd_length(force) > 80 ? .zero : force
    }

    /// Breath, weight shifts and the chest turning after the head, laid over the body in model space about the sitting
    /// spine.
    private func settle(_ p: inout CatRig.Posture, _ dt: Float, _ r: Float) {
        let b = behavior.state
        breath.update(dt, drowse: behavior.drowse * r, effort: effort)
        let chestYaw = b.chestYaw * r
        // The head keeps looking where it did, the chest having turned under it.
        p.headYaw -= chestYaw
        let lean = Pose.about(floor, .x(-b.forward * r) * .z(b.lean * r))
        p.chestMove = lean.under(Pose.about(spine, .y(chestYaw)))
        p.chestMove.t += breathChest * breath.value
        p.hipsMove = lean.under(Pose.about(spine, .y(0.3 * chestYaw)))
        p.hipsMove.t += breathHips * breath.value
    }

    /// The head rides the gait's bob, pitch and roll only as a slow average: it turns and shifts against them on the
    /// neck, so it holds its height and stays level, a little behind the body.
    private func steadyHead(_ p: inout CatRig.Posture, _ dt: Float, _ g: (y: Float, pitch: Float, roll: Float)) {
        let k = 1 - exp(-dt / headLag)
        steady.y += (g.y - steady.y) * k
        steady.pitch += (g.pitch - steady.pitch) * k
        steady.roll += (g.roll - steady.roll) * k
        let e = (y: steady.y - g.y, pitch: steady.pitch - g.pitch, roll: steady.roll - g.roll)
        // The neck moves with the body turning about the spine's middle, to first order.
        let d = rig.neck - rig.spineMid
        p.headPitch += e.pitch
        p.headRoll += e.roll
        p.headShift = [-e.roll * d.y, e.y - e.pitch * d.z, e.pitch * d.y]
    }

    // MARK: - Trips

    private func add(_ duration: Float, _ run: @escaping (Float) -> Void) {
        steps.append(Step(duration: duration, run: run))
    }

    private func leg(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ move: Waypoint.Move) {
        turn(facing(to.x - from.x, to.z - from.z))
        if move == .jump { jump(from, to) } else { walk(from, to) }
    }

    /// Two quick pats with both fore paws, chest rising a little with each.
    private func pat() {
        var up = Posture.stand
        up.pitch = 0.12
        up.lift = 0.006
        up.headPitch = 0.12
        up.fore = [0.03, -0.025]
        up.tail = [0.3, 0.15, 0]
        add(1.1) { [unowned self] u in
            keyframes([(0, .stand), (0.22, up), (0.42, .stand), (0.68, up), (0.9, .stand), (1.1, .stand)], u * 1.1)
        }
    }

    /// Up off the floor onto her seat if she lies, then up on all fours.
    private func standUp() {
        if lying.isDown {
            var from: Lying?
            add(0.8 + 0.8 * max(lying.loaf, lying.curl)) { [unowned self] u in
                let start = from ?? lying
                from = start
                lying.rise(from: start, u)
                posture = .lying(lying)
            }
        }
        add(0.8) { [unowned self] u in posture = .blend(.sit, .stand, ease(u)) }
    }

    /// A front stretch before setting off: fore paws reach forward, chest goes down and rump up with the tail raised,
    /// held with a little shiver, then back up.
    private func stretch() {
        var bow = Posture.stand
        bow.lift = -0.012
        bow.pitch = -0.25
        bow.bend = 0.05
        bow.headPitch = 0.25
        bow.fore = [0, -0.035]
        bow.tail = [0.35, 0.1, 0]
        let hold = Float.random(in: 0.5..<1.1)
        let length = 0.6 + hold + 0.5
        add(length) { [unowned self] u in
            let t = u * length
            keyframes([(0, .stand), (0.6, bow), (0.6 + hold, bow), (length, .stand)], t)
            if t > 0.6 && t < 0.6 + hold { posture.lift += 0.0015 * sin(t * 50) }
        }
    }

    private func sitDown() {
        add(0.8) { [unowned self] u in posture = .blend(.stand, .sit, ease(u)) }
    }

    /// Turns on the spot with small steps, about 2.5 rad a second.
    private func turn(_ target: Float) {
        let end = shortest(planYaw, target)
        let angle = abs(end - planYaw)
        planYaw = end
        guard angle >= 0.05 else { return }
        var start: Float?
        add(0.15 + angle / 2.5) { [unowned self] u in
            let from = start ?? yaw
            start = from
            yaw = lerp(from, shortest(from, target), ease(u))
            stepping = true
        }
    }

    /// Picks up speed over her first stride and loses it over the last, smoothly both ways.
    private func walk(_ from: SIMD3<Float>, _ to: SIMD3<Float>) {
        let distance = simd_distance(from, to)
        guard distance > 0 else { return }
        let speed = min(walkSpeed, distance / rampTime)
        let duration = distance / speed + rampTime
        let rampTime = rampTime
        // Distance covered `t` seconds into a ramp from standing to full speed.
        func ramp(_ t: Float) -> Float { speed * rampTime * (pow(t / rampTime, 3) - pow(t / rampTime, 4) / 2) }
        add(duration) { [unowned self] u in
            let t = u * duration
            var along = ramp(rampTime) + speed * (t - rampTime)
            if t < rampTime { along = ramp(t) } else if t > duration - rampTime { along = distance - ramp(duration - t) }
            group.position = simd_mix(from, to, SIMD3(repeating: along / distance))
            stepping = true
            gaze = -0.15
        }
    }

    /// Blends the posture along `keys`, (seconds, posture) in order, at `t` seconds.
    private func keyframes(_ keys: [(Float, Posture)], _ t: Float) {
        var i = 1
        while i < keys.count - 1 && t > keys[i].0 { i += 1 }
        let (t0, from) = keys[i - 1], (t1, to) = keys[i]
        posture = .blend(from, to, ease(min(max((t - t0) / (t1 - t0), 0), 1)))
    }

    /// A cat's jump: she sizes it up and gathers her weight back over her hind legs, wiggles her rump treading with her
    /// hind paws, goes still, springs off her hind legs with the fore paws already up, reaches forward in the air, lands
    /// on her fore paws first, lets the hind paws follow, and lets both sets of legs take the weight before standing up.
    private func jump(_ from: SIMD3<Float>, _ to: SIMD3<Float>) {
        let rise = (to.y - from.y) / scale
        let up: Float = rise > 0 ? 1 : 0
        let reach = simd_distance(from, to) / scale
        let air = 0.28 + 0.6 * sqrt(reach)
        // Room units above the straight line from takeoff to landing.
        let arc = 0.03 + 0.4 * max(0, to.y - from.y)
        let aim = min(max(atan2(rise, hypot(to.x - from.x, to.z - from.z) / scale), -0.6), 0.6)
        func key(_ change: (inout Posture) -> Void) -> Posture {
            var p = Posture.stand
            change(&p)
            return p
        }

        let wiggleTime = Float.random(in: 0.4..<0.8)
        let gather = key {
            $0.lift = -0.022; $0.back = 0.008; $0.pitch = lerp(-0.1, 0.08, up); $0.bend = 0.05; $0.headPitch = aim * 0.9
            $0.tail = [-0.3, -0.1, 0.1]
        }
        var coil = gather
        coil.lift = -0.032
        coil.back = 0.012
        let prepare = 0.35 + wiggleTime + 0.12
        add(prepare) { [unowned self] u in
            let t = u * prepare
            group.position = from
            keyframes([(0, .stand), (0.35, gather), (0.35 + wiggleTime, coil)], t)
            // The rump sways side to side, the hind paws treading in turn, then she goes still.
            let w = min(max((t - 0.35) / wiggleTime, 0), 1)
            let sway = sin(w * .pi) * sin((t - 0.35) * .pi * 2 * 4.5)
            wiggle = 0.12 * sway
            tread = [0.005 * max(0, sway), 0.005 * max(0, -sway)]
            posture.tail[2] += 0.3 * sway
        }

        let launch = key {
            $0.lift = 0.015; $0.back = -0.022; $0.pitch = lerp(0.05, 0.4, up); $0.bend = -0.1; $0.headPitch = aim * 0.5
            $0.fore = [0.03, -0.035]; $0.tail = [0.1, 0, 0]
        }
        add(0.14) { [unowned self] u in
            group.position = from
            free = true
            wiggle = 0
            tread = .zero
            posture = .blend(coil, launch, ease(u))
        }

        let flight = key {
            $0.back = -0.02; $0.pitch = lerp(-0.25, 0.2, up); $0.bend = -0.12; $0.headPitch = aim * 0.3
            $0.fore = [0.02, -0.04]; $0.hind = [0.025, 0.035]; $0.tail = [0.2, 0.1, 0]
        }
        let reachDown = key {
            $0.back = -0.008; $0.pitch = lerp(-0.3, -0.02, up); $0.bend = 0.05; $0.headPitch = lerp(0.15, -0.1, up)
            $0.fore = [0, -0.03]; $0.hind = [0.035, 0]; $0.tail = [0.15, 0.1, 0]
        }
        var contact = reachDown
        contact.fore = [0, -0.02]
        add(air) { [unowned self] u in
            free = true
            var at = simd_mix(from, to, SIMD3(repeating: u))
            at.y += 4 * arc * u * (1 - u)
            group.position = at
            keyframes([(0, launch), (0.3, flight), (0.75, reachDown), (1, contact)], u)
        }

        // The fore legs fold under the landing, then the hind paws come down and fold in turn; the head stays level.
        let forward = key {
            $0.lift = -0.02; $0.back = -0.012; $0.pitch = -0.18; $0.bend = 0.08; $0.headPitch = 0.13
            $0.fore = [0, -0.01]; $0.hind = [0.03, 0]; $0.tail = [0.1, 0.05, 0]
        }
        let settle = key { $0.lift = -0.028; $0.back = -0.004; $0.pitch = -0.03; $0.bend = 0.04; $0.headPitch = 0.02 }
        add(0.55) { [unowned self] u in
            group.position = to
            free = true
            keyframes([(0, contact), (0.1, forward), (0.24, settle), (0.55, .stand)], u * 0.55)
        }
    }
}
