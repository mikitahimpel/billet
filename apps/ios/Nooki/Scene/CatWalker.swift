import Foundation
import RealityKit
import simd

private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
private func ease(_ t: Float) -> Float { t * t * (3 - 2 * t) }
private func shortest(_ a: Float, _ b: Float) -> Float { a + atan2(sin(b - a), cos(b - a)) }
private func facing(_ dx: Float, _ dz: Float) -> Float { atan2(-dx, -dz) }

/// Mochi on her two skeletons, ported from nooki-scene/src/three/catWalker.js and catSeat.js. Sitting she looks around,
/// twitches her ears and waves her tail on the seated splat; given a route she swaps to the standing one crouched in the
/// seated silhouette, gets up, walks and jumps along its waypoints, and sits down at the other end.
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
    /// tail joint (negative lowers it).
    private struct Posture {
        var lift: Float = 0, back: Float = 0, pitch: Float = 0, bend: Float = 0, headPitch: Float = 0
        var fore = SIMD2<Float>.zero, hind = SIMD2<Float>.zero
        var tail: [Float] = [0, 0, 0]

        static let stand = Posture()
        // Rump down on folded hind legs, chest up on straight fore legs, tail lying behind her: the seated splat's
        // silhouette, with the head where the seated splat has it, for the swap between the two.
        static let sit = Posture(lift: -0.005, back: -0.005, pitch: 0.5, bend: -0.7, headPitch: -0.2, hind: [0, -0.035],
                                 tail: [-1.1, -0.4, -0.2])

        static func blend(_ a: Posture, _ b: Posture, _ t: Float) -> Posture {
            Posture(lift: lerp(a.lift, b.lift, t), back: lerp(a.back, b.back, t), pitch: lerp(a.pitch, b.pitch, t),
                    bend: lerp(a.bend, b.bend, t), headPitch: lerp(a.headPitch, b.headPitch, t),
                    fore: simd_mix(a.fore, b.fore, SIMD2(repeating: t)), hind: simd_mix(a.hind, b.hind, SIMD2(repeating: t)),
                    tail: zip(a.tail, b.tail).map { lerp($0, $1, t) })
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
    /// The standing skeleton, posed every frame whichever splat shows.
    let standing: CatRig
    let seated: CatRig

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
    private var seatAmount: Float = 1

    /// `group` is what she moves and turns, `scale` turns model units into room units. She starts sitting at the
    /// route's end (or at `group` without a route) facing `rests[1]`; a route runs from the first resting spot to the
    /// second, `rests` being her yaws at those two spots.
    init(group: Entity, standing: CatRig, seated: CatRig, scale: Float, rests: [Float], route: [Waypoint] = [],
         wandering: Bool) {
        self.group = group
        self.standing = standing
        self.seated = seated
        self.scale = scale
        self.wandering = wandering
        behavior = CatBehavior(tailJoints: seated.pose.tail.count)
        gait = Gait(standing.legs, speed: walkSpeed / scale)
        tailSpring = TailSpring(standing.tailDirections)
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
        wait = Float.random(in: 6..<12)
        seated.entity?.position = seated.mount
        fade(1)
    }

    var moving: Bool { !steps.isEmpty }
    var canTrip: Bool { main != nil }
    /// The destination she is at or on her way to, nil at home.
    var place: String? { away?.id }

    func pet() {
        behavior.pet()
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
        if !moving, wandering && canTrip || away != nil {
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
            if steps.isEmpty { wait = Float.random(in: 10..<22) }
        }
        group.orientation = .y(yaw)
        if dt > 0 {
            frame.velocity = (group.position - last.at) / dt
            frame.yawRate = (yaw - last.yaw) / dt
        }
        frame.at = group.position
        frame.yaw = yaw
        last = (group.position, yaw)
        behavior.update(dt)
        resting += ((moving ? 0 : 1) - resting) * (1 - exp(-dt * 4))
        pose(dt)
        updateSeat(headPitch: standing.pose.headPitch - posture.headPitch)
    }

    /// 1 shows the seated cat, 0 the standing one, cutting from one to the other halfway: their collars, bells and paws
    /// sit a little apart, so any frame showing both shows two of each.
    private func fade(_ amount: Float) {
        seatAmount = amount
        seated.entity?.isEnabled = amount > 0.5
        standing.entity?.isEnabled = amount <= 0.5
    }

    /// Shows whichever of her two splats this walker last showed; the rigs are shared with other rooms' walkers.
    func show() {
        seated.entity?.position = seated.mount
        fade(seatAmount)
    }

    /// Writes the posture, gait, and the resting behavior as far as she is at rest, into the standing rig.
    private func pose(_ dt: Float) {
        gait.update(dt, frame, stepping: stepping, planted: !free)
        let g = gait.body()
        let s = posture
        let b = behavior.state
        let r = resting
        var p = standing.pose
        p.lift = s.lift + g.y
        p.back = s.back
        p.pitch = s.pitch + g.pitch
        p.roll = g.roll
        p.bend = s.bend
        p.wiggle = wiggle
        // Walking she watches the floor ahead.
        lookPitch += (gaze - lookPitch) * (1 - exp(-dt * 4))
        p.headPitch = s.headPitch + lerp(lookPitch, b.pitch, r)
        p.headYaw = lerp(0.12 * sin(time * 0.6), b.yaw, r)
        p.headRoll = b.roll * r
        steadyHead(&p, dt, g)
        p.earLeft = b.earLeft * r
        p.earRight = b.earRight * r
        p.earsBack = b.earsBack * r
        // On the move the ears point ahead; the eyes blink whatever she does, but droop only at rest.
        p.earTurnLeft = lerp(-0.1, b.earTurnLeft, r)
        p.earTurnRight = lerp(-0.1, b.earTurnRight, r)
        p.lidLeft = max(behavior.blink, b.lidLeft * r)
        p.lidRight = max(behavior.blink, b.lidRight * r)
        for (i, leg) in standing.legs.enumerated() {
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
            p.tail[i].sway = lerp((0.06 + 0.05 * fi) * sin(time * 1.6 - fi * 0.8), b.tailSway[i], r)
            p.tail[i].lift = s.tail[min(i, s.tail.count - 1)] + 0.1 * gait.amount + b.tailLift[i] * r + spring.lift
            p.tail[i].lean = spring.lean
        }
        standing.pose = p
        // Hidden, the standing skeleton still poses: the seated head and the tail's swing follow it.
        standing.update(skinning: seatAmount <= 0.5)
        tailPush = tailForce(dt)
    }

    /// Poses the seated skeleton: head and ears as the standing one holds them, so the two heads stay on each other
    /// through a swap, `headPitch` being the standing head's own nod without its posture; the tail sweeps along the
    /// floor with the resting behavior.
    private func updateSeat(headPitch: Float) {
        let s = standing.pose
        let b = behavior.state
        var p = seated.pose
        p.headYaw = s.headYaw
        p.headPitch = headPitch
        p.headRoll = s.headRoll
        p.earLeft = s.earLeft
        p.earRight = s.earRight
        p.earsBack = s.earsBack
        p.earTurnLeft = s.earTurnLeft
        p.earTurnRight = s.earTurnRight
        p.lidLeft = s.lidLeft
        p.lidRight = s.lidRight
        let lastJoint = p.tail.count - 1
        for i in p.tail.indices {
            p.tail[i].sway = 1.5 * b.tailSway[i]
            p.tail[i].lift = i == lastJoint ? 0.6 * b.tailLift[i] : 0
        }
        seated.pose = p
        // The seated splat only needs skinning while it shows.
        if seatAmount > 0.5 { seated.update() }
    }

    /// Minus the acceleration of the tail's root over the last frames, in model units and axes.
    private func tailForce(_ dt: Float) -> SIMD3<Float> {
        guard let base = standing.tailJoints.first else { return .zero }
        let local = simd_quatf.y(yaw).act(standing.hipsPose.apply(base) * scale) + group.position
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

    /// The head rides the gait's bob, pitch and roll only as a slow average: it turns and shifts against them on the
    /// neck, so it holds its height and stays level, a little behind the body.
    private func steadyHead(_ p: inout CatRig.Posture, _ dt: Float, _ g: (y: Float, pitch: Float, roll: Float)) {
        let k = 1 - exp(-dt / headLag)
        steady.y += (g.y - steady.y) * k
        steady.pitch += (g.pitch - steady.pitch) * k
        steady.roll += (g.roll - steady.roll) * k
        let e = (y: steady.y - g.y, pitch: steady.pitch - g.pitch, roll: steady.roll - g.roll)
        // The neck moves with the body turning about the spine's middle, to first order.
        let d = standing.neck - standing.spineMid
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

    /// From the seated splat to the standing one crouched in its silhouette, then up.
    private func standUp() {
        add(0.05) { [unowned self] u in fade(1 - u) }
        add(0.7) { [unowned self] u in posture = .blend(.sit, .stand, ease(u)) }
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
        add(0.05) { [unowned self] u in fade(u) }
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
