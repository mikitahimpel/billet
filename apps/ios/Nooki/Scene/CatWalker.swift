import DecorInterface
import Foundation
import Pet
import RealityKit
import simd

private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
private func ease(_ t: Float) -> Float { t * t * (3 - 2 * t) }
/// Like `ease`, and with no acceleration at either end.
private func glide(_ t: Float) -> Float { t * t * t * (t * (6 * t - 15) + 10) }
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

/// Mochi on her two skeletons, ported from nooki-scene/src/three/catWalker.js and catSeat.js. Sitting she looks around,
/// twitches her ears and waves her tail on the seated splat, and lies down in a loaf to doze when tired; given a route
/// she swaps to the standing one crouched in the seated silhouette, gets up, walks and jumps along its waypoints, and
/// sits down at the other end.
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
    struct Posture {
        var lift: Float = 0, back: Float = 0, pitch: Float = 0, bend: Float = 0, headPitch: Float = 0, seat: Float = 0
        var fore = SIMD2<Float>.zero, hind = SIMD2<Float>.zero
        /// Moves the left and the right hind paw back by its own amount on top of `hind`, model units: while she
        /// changes posture they step to their new place one after the other.
        var hindSplit = SIMD2<Float>.zero
        var tail: [Float] = [0, 0, 0]
        /// Swings each tail joint to her left, radians.
        var sway: [Float] = [0, 0, 0]

        static let stand = Posture()

        /// The angle each tail joint turns its bone by: a smooth curve keeps them close, a kink is one far larger.
        var tailBends: [Float] {
            zip(tail, sway).map { lift, sway in
                let (cs, cl) = (cos(sway), cos(lift))
                return acos(min(max((cs + cl + cs * cl - 1) / 2, -1), 1))
            }
        }
        // Rump down with the hind paws drawn in under her, chest up on straight fore legs, tail round her left side:
        // of the standing splat's upright postures the one whose outline lies closest on the seated splat's from the
        // sides, front, back and above (tools/cat-motion, `fit`), both leaning forward by `swapLean`, with the head
        // exactly where the seated splat has it, for the swap between the two.
        static let sit = Posture(lift: -0.0194, back: -0.0288, pitch: 0.75, bend: -0.7, headPitch: 0, seat: 1,
                                 fore: [-0.006, -0.005], hind: [0.02, -0.12], tail: [-0.3, -0.7, -0.3], sway: [0.9, 0.95, 1.1])
        /// Radians both splats lean forward about the floor where one takes over from the other: sitting, a cat
        /// leans over her fore paws before she gets up and comes back upright after she sits down.
        static let swapLean: Float = 0.16
        // Lying with her paws tucked under her and the tail along her side.
        static let loaf = Posture(lift: -0.065, bend: 0.05, headPitch: 0.05, fore: [0, 0.035], hind: [0, -0.03],
                                  tail: [-0.9, -0.7, -0.6], sway: [0.7, 0.6, 0.6])

        /// How much of a behaviour's tail-tip lift plays at this body height: all of it down to a crouch's -0.035,
        /// none in the loaf, whose tail rests on the floor and would fold back up at the tip.
        static func tipLiftShare(lift: Float) -> Float { 1 - smoothstep(-lift, 0.035, 0.065) }

        static func blend(_ a: Posture, _ b: Posture, _ t: Float) -> Posture {
            Posture(lift: lerp(a.lift, b.lift, t), back: lerp(a.back, b.back, t), pitch: lerp(a.pitch, b.pitch, t),
                    bend: lerp(a.bend, b.bend, t), headPitch: lerp(a.headPitch, b.headPitch, t), seat: lerp(a.seat, b.seat, t),
                    fore: simd_mix(a.fore, b.fore, SIMD2(repeating: t)), hind: simd_mix(a.hind, b.hind, SIMD2(repeating: t)),
                    hindSplit: simd_mix(a.hindSplit, b.hindSplit, SIMD2(repeating: t)),
                    tail: zip(a.tail, b.tail).map { lerp($0, $1, t) },
                    sway: zip(a.sway, b.sway).map { lerp($0, $1, t) })
        }

        /// When each part of her moves within a change of posture, as shares of its time: a cat does not morph from
        /// one pose to the next, her parts go in turn and overlap.
        struct Order {
            var pitch, lift, bend, back, head, tail, fore, hindLeft, hindRight: ClosedRange<Float>

            // Up from sitting: the chest and head go forward first, the hind legs push the rump up (most of the push
            // in the first half), the hind paws step back out from under her one after the other, the tail comes up
            // last.
            static let rising = Order(pitch: 0.05...0.7, lift: 0...0.75, bend: 0.08...0.8, back: 0...0.65, head: 0...0.5,
                                      tail: 0.25...1, fore: 0.1...0.6, hindLeft: 0.3...0.62, hindRight: 0.56...0.9)
            // Down to sitting: the hind paws step in under her, the rump goes down onto them, the chest comes up, the
            // head settles and the tail comes round last.
            static let sitting = Order(pitch: 0.2...0.85, lift: 0.15...0.9, bend: 0.25...0.95, back: 0.1...0.75,
                                       head: 0.35...0.9, tail: 0.4...1, fore: 0.3...0.7, hindLeft: 0...0.3,
                                       hindRight: 0.22...0.52)

            func share(_ range: ClosedRange<Float>, _ u: Float) -> Float {
                min(max((u - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            }
        }

        /// `u` of the way from `a` to `b` in time, each part as far as `order` has it by then.
        static func blend(_ a: Posture, _ b: Posture, _ u: Float, _ order: Order) -> Posture {
            guard u < 1 else { return b }
            func at(_ range: ClosedRange<Float>) -> Float { glide(order.share(range, u)) }
            let (tail, head, fore) = (at(order.tail), at(order.head), at(order.fore))
            let reach = b.hind.y + b.hindSplit - a.hind.y - a.hindSplit
            return Posture(lift: lerp(a.lift, b.lift, at(order.lift)), back: lerp(a.back, b.back, at(order.back)),
                           pitch: lerp(a.pitch, b.pitch, at(order.pitch)), bend: lerp(a.bend, b.bend, at(order.bend)),
                           headPitch: lerp(a.headPitch, b.headPitch, head), seat: lerp(a.seat, b.seat, head),
                           fore: simd_mix(a.fore, b.fore, SIMD2(repeating: fore)),
                           hind: [lerp(a.hind.x, b.hind.x, at(order.lift)), a.hind.y],
                           hindSplit: a.hindSplit + reach * SIMD2(at(order.hindLeft), at(order.hindRight)),
                           tail: zip(a.tail, b.tail).map { lerp($0, $1, tail) },
                           sway: zip(a.sway, b.sway).map { lerp($0, $1, tail) })
        }
    }

    /// A change of posture under way. It runs beside the steps, so the next one may start before she is all the way
    /// there.
    private struct Change {
        let from, to: Posture
        let order: Posture.Order
        let duration: Float
        var time: Float = 0
    }

    // Model units a hind paw clears the floor by as it steps to its new place under her.
    private static let pawStep: Float = 0.007
    // How far she squashes down into a swap of her splats, as a share of her height; the body that takes over comes
    // back up from it, so the cut falls inside one move.
    private static let swapSquash: Float = 0.035

    private struct Step {
        let duration: Float
        let run: (_ u: Float) -> Void
        var time: Float = 0
        /// A step with no set length: called with the frame's seconds until it says it is done.
        var open: ((_ dt: Float) -> Bool)?
        /// Where a walk along the floor is headed, for the step before it to round the corner into it.
        var target: SIMD3<Float>?
        /// Part of a chase, dropped when what she chases moves.
        var chase = false
    }

    // Room units from a corner of her path where she starts to turn into the next leg, less than the margin her
    // routes keep from the furniture (Occupancy.clearance).
    private static let cornerCut: Float = 0.03

    /// How quickly she gets about; a game sets her eager pace and gives her usual one back after.
    var pace = CatPace.usual
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
    /// Her lying splats, the loaf and the curled sleep, cut to in one frame from sitting. Without one she lies down
    /// in her loaf on the standing splat instead, and asks for it (`needsBody`); one that comes takes over.
    private(set) var bodies: [NookiRestPose: CatRig]
    var needsBody: ((NookiRestPose) -> Void)?
    /// The body the brain has her rest in; `sit` whenever she is on the move.
    private(set) var rest = NookiRestPose.sit
    /// Seconds since the last cut between rest bodies, for the settle squash.
    private var settleTime: Float = 10
    /// The standing skeleton, posed every frame whichever splat shows.
    let standing: CatRig
    let seated: CatRig

    private let group: Entity
    private let scale: Float
    private let gait: Gait
    private let tailSpring: TailSpring
    /// Where she rests between outings, facing `homeYaw`.
    private var home: SIMD3<Float>
    private var homeYaw: Float
    /// The route's far end, where `trip()` takes her.
    private(set) var main: Destination?
    /// Where she is sitting now, nil at home.
    private var away: Destination?
    private var yaw: Float
    private var planYaw: Float = 0
    private var steps: [Step] = []
    private var wait: Float
    private var time: Float = 0
    private var posture = Posture.sit
    private var rested = Glide(value: 1)
    private var resting: Float { min(max(rested.value, 0), 1) }
    private var lookPitch = Glide(value: 0)
    private var gaze: Float = 0
    /// How far the head turns ahead of the body round a turn, and how far it has got.
    private var lead: Float = 0
    private var lookYaw = Glide(value: 0)
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
    /// Seconds her sitting and standing bodies take to dissolve into each other; 0 cuts in one frame.
    var dissolve: Float = 0
    private var mixing: (time: Float, seated: Bool)?
    private var change: Change?
    /// Her speed along the floor and her turning as she walks, carried from one leg into the next.
    private var travel: (speed: Float, turn: Glide) = (0, Glide(value: 0))
    private var squash: (value: Float, speed: Float, goal: Float, shown: Float) = (0, 0, 0, 0)
    private var lean: (value: Float, speed: Float, goal: Float) = (0, 0, 0)
    private var breath = Breath()
    private var effort: Float = 0
    private var lying = false
    private var viewer: SIMD3<Float>?
    /// Where her spine bends sitting, and the floor under it, in the standing cat's model space.
    private let spine: SIMD3<Float>
    private let floor: SIMD3<Float>

    /// `group` is what she moves and turns, `scale` turns model units into room units. She starts sitting at the
    /// route's end (or at `group` without a route) facing `rests[1]`; a route runs from the first resting spot to the
    /// second, `rests` being her yaws at those two spots.
    init(group: Entity, standing: CatRig, seated: CatRig, bodies: [NookiRestPose: CatRig] = [:], scale: Float,
         rests: [Float], route: [Waypoint] = [], wandering: Bool) {
        self.group = group
        self.standing = standing
        self.seated = seated
        self.bodies = bodies.filter { $0.key != .sit }
        self.scale = scale
        self.wandering = wandering
        behavior = CatBehavior(tailJoints: seated.pose.tail.count)
        gait = Gait(standing.legs, speed: CatPace.usual.walkSpeed / scale)
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
        spine = seated.spineMid + seated.mount
        floor = [spine.x, 0, spine.z]
        wait = Float.random(in: 6..<12)
        seated.entity?.position = seated.mount
        fade(1)
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

    /// Rests her in `pose`: a lying splat is cut to in one frame with a little squash as she settles, as the web lab
    /// does; without one she lies down in her loaf on the standing splat. Only while she is still.
    func settle(_ pose: NookiRestPose) {
        takeOver()
        guard !moving, pose != rest else { return }
        let from = rest
        rest = pose
        if pose != .sit, bodies[pose] == nil { needsBody?(pose) }
        if bodies[pose] != nil || bodies[from] != nil {
            settleTime = 0
            if lying { getUp() } else { fade(seatAmount) }
        }
        if bodies[pose] == nil {
            if pose == .sit, lying { getUp() }
            if pose != .sit, !lying { lieDown() }
        }
    }

    /// Gives her a lying body loaded after she was built, or takes one she is not resting in back with nil.
    func setBody(_ pose: NookiRestPose, _ rig: CatRig?) {
        guard pose != .sit, rig != nil || pose != rest else { return }
        bodies[pose] = rig
        if let rig { rig.entity?.position = rig.mount }
        takeOver()
    }

    /// A body that came while she lay in her loaf on the standing splat is cut to in one frame.
    private func takeOver() {
        guard !moving, lying, rest != .sit, bodies[rest] != nil else { return }
        lying = false
        posture = .sit
        settleTime = 0
        fade(1)
    }

    /// Gets up for a couple of paw pats on what she is on, and sits again.
    func pats() {
        guard !moving else { return }
        leaveBody()
        standUp()
        pat()
        sitDown()
    }

    /// Gets up and drops into a low crouch, rump up and wiggling, and sits again.
    func crouch() {
        guard !moving else { return }
        leaveBody()
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
        leaveBody()
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
        leaveBody()
        standUp()
        planYaw = yaw
        let home = yaw
        for third in 1...3 { turn(home + Float(third) * 2 * .pi / 3) }
        turn(home)
        sitDown()
    }

    /// Back from a lying splat to the seated one in one frame, before she gets up.
    private func leaveBody() {
        guard rest != .sit else { return }
        if bodies[rest] != nil { settleTime = 0 }
        rest = .sit
        fade(seatAmount)
    }

    /// Moves where she rests and the way to the route's far end, as the player moves the bed and the tree. She is set
    /// down at the new place at once when anything changed.
    func rehome(at position: SIMD3<Float>, yaw: Float, main next: Destination?) {
        let samePath = main?.path.map(\.at) == next?.path.map(\.at) && main?.rest == next?.rest
        guard position != home || yaw != homeYaw || !samePath else { return }
        home = position
        homeYaw = yaw
        main = next
        snapHome()
    }

    /// Back on her bed at once, sitting, with whatever she was doing dropped.
    func snapHome() {
        steps = []
        chased = nil
        travel = (0, Glide(value: 0))
        away = nil
        lying = false
        rest = .sit
        posture = .sit
        stepping = false
        change = nil
        tread = .zero
        squash.goal = 0
        lean.goal = 0
        group.position = home
        yaw = homeYaw
        planYaw = homeYaw
        last = (home, homeYaw)
        fade(1)
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
        let eyes = standing.eyes
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
        // With no way there she stays where she is, rather than walk through what stands in the way.
        guard let legs = plan(to: destination) else {
            wait = max(wait, 5)
            return
        }
        chased = nil
        planYaw = yaw
        behavior.stir(0.2)
        leaveBody()
        standUp()
        if stretch { self.stretch() }
        for leg in legs { self.leg(leg.from, leg.to, leg.move) }
        if let arrive = destination?.arrive { add(0.01) { _ in arrive() } }
        if destination?.play == true { pat() }
        turn(destination?.rest ?? homeYaw)
        sitDown()
        away = destination
    }

    /// Where what she chases was when she last planned her way to it, and how long she has stood there since.
    private var chased: (point: SIMD3<Float>, idle: Float)?
    /// How much faster than her walk she runs after something far off.
    private static let dash: Float = 1.7

    /// Runs her after `point` on the floor from wherever she is, and again whenever it has moved: she takes the new
    /// way without stopping, runs while it is far and slows closing in, and stays on her feet when she gets there,
    /// sitting down only once it has kept still a while. Ignored while she does anything but chase.
    func chase(_ point: SIMD3<Float>, id: String) {
        if moving {
            guard steps.contains(where: \.chase) else { return }
            if let chased, simd_distance(chased.point, point) < 0.03 { return }
        }
        // With no way round to it she keeps to what she was doing.
        guard let corners = detour(group.position, point) else { return }
        if moving {
            steps.removeAll(where: \.chase)
        } else {
            planYaw = yaw
            behavior.stir(0.2)
            leaveBody()
            standUp()
        }
        chased = (point, 0)
        var from = group.position
        for corner in corners + [point] {
            walk(from, corner, chase: true)
            from = corner
        }
        away = Destination(id: id, path: [Waypoint(at: point, move: .jump)], rest: yaw)
    }

    /// Springs onto `point` from where she stands, with the crouch and wiggle of a jump, and pats what she landed
    /// on; from a paw's reach she only pats. Only while she is still.
    func pounce(on point: SIMD3<Float>, id: String) {
        guard !moving else { return }
        let here = group.position
        planYaw = yaw
        leaveBody()
        standUp()
        if simd_distance(here, point) > 0.05 {
            turn(facing(point.x - here.x, point.z - here.z))
            jump(here, point)
        }
        pat()
        chased = (point, 0)
        away = Destination(id: id, path: [Waypoint(at: point, move: .jump)], rest: yaw)
    }

    /// Height below which a waypoint counts as standing on the floor.
    var floorTop: Float = 0.04
    /// A round obstacle on the floor, center and radius in the floor plane, that walks between destinations go around.
    var keepOut: (center: SIMD2<Float>, radius: Float)?
    /// What the player has stood on the floor: walks between destinations take the route around it.
    var avoid: Occupancy?

    private struct Leg {
        let from, to: SIMD3<Float>
        let move: Waypoint.Move
    }

    /// Every leg of the way to `destination`, or home with nil, from where she is: from one destination to another
    /// only down to the floor and across it. Nil when what stands on the floor leaves her no way.
    private func plan(to destination: Destination?) -> [Leg]? {
        let points = [Waypoint(at: home)] + (away?.path ?? [])
        if let destination, away != nil, let exit = floorExit(points), let entry = floorEntry(destination.path) {
            let join = destination.path[entry].at
            guard let down = retrace(points, downTo: exit), let across = floorLegs(from: points[exit].at, to: join),
                let on = follow(destination, from: entry + 1, at: join)
            else { return nil }
            return down + across + on
        }
        guard let back = retrace(points, downTo: 0) else { return nil }
        guard let destination else { return back }
        return follow(destination, from: 0, at: home).map { back + $0 }
    }

    /// Back along the way she came, each leg crossed the way it was reached, until she stands on `points[index]`.
    private func retrace(_ points: [Waypoint], downTo index: Int) -> [Leg]? {
        var way: [Leg] = []
        for i in stride(from: points.count - 1, to: index, by: -1) {
            guard let next = legs(from: points[i].at, to: points[i - 1].at, points[i].move) else { return nil }
            way += next
        }
        return way
    }

    /// One leg; a walk along the floor goes round what the player stood in the way (found when she sets off).
    private func legs(from: SIMD3<Float>, to: SIMD3<Float>, _ move: Waypoint.Move) -> [Leg]? {
        guard move == .walk, avoid != nil, from.y < floorTop, to.y < floorTop else {
            return [Leg(from: from, to: to, move: move)]
        }
        return floorLegs(from: from, to: to)
    }

    private func floorLegs(from: SIMD3<Float>, to: SIMD3<Float>) -> [Leg]? {
        guard let corners = detour(from, to) else { return nil }
        var at = from
        return (corners + [to]).map { corner in
            defer { at = corner }
            return Leg(from: at, to: corner, move: .walk)
        }
    }

    private func follow(_ destination: Destination, from index: Int, at start: SIMD3<Float>) -> [Leg]? {
        var way: [Leg] = []
        var from = start
        for point in destination.path[index...] {
            guard let next = legs(from: from, to: point.at, point.move) else { return nil }
            way += next
            from = point.at
        }
        return way
    }

    /// The last floor point on the way out to where she is: as far as she needs to come back.
    private func floorExit(_ points: [Waypoint]) -> Int? {
        points.indices.dropFirst().last { points[$0].at.y < floorTop }
    }

    /// The floor point a destination's path is joined at: the one its last jump takes off from, else its last on
    /// the floor.
    private func floorEntry(_ path: [Waypoint]) -> Int? {
        let takeoff = path.indices.dropLast().last { path[$0].at.y < floorTop && path[$0 + 1].move == .jump }
        return takeoff ?? path.indices.last { path[$0].at.y < floorTop }
    }

    /// Corners of the walk from `a` to `b` round what stands on the floor, nil when that leaves no way. With no
    /// floor plan, corners around `keepOut` when the straight walk would cross it, always on its front (+z) side,
    /// where the floor is open; each new leg is checked again once.
    private func detour(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> [SIMD3<Float>]? {
        guard let avoid else { return around(a, b) }
        return avoid.route(from: (Double(a.x), Double(a.z)), to: (Double(b.x), Double(b.z)))?
            .map { SIMD3(Float($0.x), a.y, Float($0.z)) }
    }

    private func around(_ a: SIMD3<Float>, _ b: SIMD3<Float>, depth: Int = 2) -> [SIMD3<Float>] {
        guard let keepOut, depth > 0 else { return [] }
        let a2 = SIMD2(a.x, a.z), d = SIMD2(b.x, b.z) - a2
        let t = simd_clamp(simd_dot(keepOut.center - a2, d) / max(simd_length_squared(d), 1e-6), 0, 1)
        var side = a2 + t * d - keepOut.center
        guard simd_length(side) < keepOut.radius else { return [] }
        if side.y < 0 || simd_length(side) < 1e-4 { side.y = abs(side.y) + 0.05 }
        let flat = keepOut.center + simd_normalize(side) * keepOut.radius * 1.45
        let corner = SIMD3(flat.x, a.y, flat.y)
        return around(a, corner, depth: depth - 1) + [corner] + around(corner, b, depth: depth - 1)
    }

    func update(_ dt: Float) {
        time += dt
        settleTime += dt
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
        lead = 0
        if !steps.isEmpty {
            steps[0].time += dt
            let step = steps[0]
            let done: Bool
            if let open = step.open {
                done = open(dt)
            } else {
                let u = min(step.time / step.duration, 1)
                step.run(u)
                done = u >= 1
            }
            if done { steps.removeFirst() }
            // A step that ends by handing over to the next has not moved her this frame; the next one does.
            if done, step.open != nil, let next = steps.first?.open {
                steps[0].time += dt
                if next(dt) { steps.removeFirst() }
            }
            if steps.isEmpty { wait = Float.random(in: 10..<22) * lerp(1.6, 0.6, behavior.mood.energy) }
        }
        if !moving, let c = chased {
            // What she chased has kept still long enough: she sits down by it.
            chased = c.idle + dt < 1.2 ? (c.point, c.idle + dt) : nil
            if chased == nil { sitDown() }
        }
        advanceChange(dt)
        advanceMix(dt)
        // Tired she lies down to doze, and gets up again once rested.
        if !directed && !moving && !lying && behavior.drowse > 0.7 && behavior.mood.energy < 0.3 { lieDown() }
        else if !directed && !moving && lying && behavior.mood.energy > 0.5 { getUp() }
        takeOver()
        behavior.napping = lying || rest != .sit
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
        behavior.update(dt, eyes: standing.eyes)
        rested.follow(moving ? 0 : 1, rate: 7, dt)
        pose(dt)
        updateSeat(headPitch: standing.pose.headPitch - posture.headPitch)
        updateSquash(dt)
    }

    private func advanceChange(_ dt: Float) {
        guard var c = change else { return }
        c.time += dt
        let u = min(c.time / c.duration, 1)
        posture = .blend(c.from, c.to, u, c.order)
        // Each hind paw lifts while it is on its way.
        func lift(_ range: ClosedRange<Float>) -> Float { Self.pawStep * sin(c.order.share(range, u) * .pi) }
        let steps = c.from.hind.y + c.from.hindSplit != c.to.hind.y + c.to.hindSplit
        tread = steps ? [lift(c.order.hindLeft), lift(c.order.hindRight)] : .zero
        change = u < 1 ? c : nil
    }

    /// The squash eases to its goal as a lightly damped spring, so she bounces once coming out of it. A still cat
    /// writes no scale.
    private func updateSquash(_ dt: Float) {
        let n = max(1, Int((dt * 120).rounded(.up)))
        let h = dt / Float(n)
        if lean.goal != 0 || lean.value != 0 || lean.speed != 0 {
            for _ in 0..<n {
                lean.speed += (11 * 11 * (lean.goal - lean.value) - 2 * 0.8 * 11 * lean.speed) * h
                lean.value += lean.speed * h
            }
            if lean.goal == 0, abs(lean.value) < 5e-4, abs(lean.speed) < 5e-3 { (lean.value, lean.speed) = (0, 0) }
        }
        guard squash.goal != 0 || squash.value != 0 || squash.speed != 0 else { return }
        for _ in 0..<n {
            squash.speed += (20 * 20 * (squash.goal - squash.value) - 2 * 0.5 * 20 * squash.speed) * h
            squash.value += squash.speed * h
        }
        if squash.goal == 0, abs(squash.value) < 5e-4, abs(squash.speed) < 5e-3 { (squash.value, squash.speed) = (0, 0) }
        guard squash.value != squash.shown else { return }
        squash.shown = squash.value
        let scale = SIMD3<Float>(1 + squash.value / 2, 1 - squash.value, 1 + squash.value / 2)
        standing.entity?.scale = scale
        seated.entity?.scale = scale
    }

    /// 1 shows the seated cat, 0 the standing one, cutting from one to the other halfway: their collars, bells and paws
    /// sit a little apart, so any frame showing both shows two of each.
    private func fade(_ amount: Float) {
        if mixing != nil {
            mixing = nil
            seated.entity?.components.remove(OpacityComponent.self)
            standing.entity?.components.remove(OpacityComponent.self)
        }
        seatAmount = amount
        let resting = amount > 0.5
        let body = bodies[rest] == nil ? nil : rest
        seated.entity?.isEnabled = resting && body == nil
        for (pose, rig) in bodies { rig.entity?.isEnabled = resting && body == pose }
        standing.entity?.isEnabled = !resting
    }

    /// Shows her sitting body or her standing one in place of the other: at once, or over `dissolve` with the new
    /// one coming in over the old before the old goes, so she is never seen through.
    private func swap(seated on: Bool) {
        fade(on ? 1 : 0)
        guard dissolve > 0, bodies[rest] == nil else { return }
        mixing = (0, on)
        advanceMix(0)
    }

    private func advanceMix(_ dt: Float) {
        guard var m = mixing else { return }
        m.time += dt
        let u = min(m.time / dissolve, 1)
        guard u < 1 else { return fade(seatAmount) }
        mixing = m
        let (new, old) = m.seated ? (seated, standing) : (standing, seated)
        old.entity?.isEnabled = true
        new.entity?.components.set(OpacityComponent(opacity: min(1, 2 * u)))
        old.entity?.components.set(OpacityComponent(opacity: min(1, 2 - 2 * u)))
    }

    /// Shows whichever of her two splats this walker last showed; the rigs are shared with other rooms' walkers.
    func show() {
        seated.entity?.position = seated.mount
        for rig in bodies.values { rig.entity?.position = rig.mount }
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
        p.headSeat = s.seat
        // Walking she watches the floor ahead.
        lookPitch.follow(gaze, rate: 7, dt)
        // Turning, the head goes first and the body comes round after it.
        lookYaw.follow(lead, rate: 16, dt)
        p.headPitch = s.headPitch + lerp(lookPitch.value, b.pitch, r)
        p.headYaw = lerp(0.12 * noise(time * 0.5, 8) + lookYaw.value, b.yaw, r)
        p.headRoll = b.roll * r
        steadyHead(&p, dt, g)
        settle(&p, dt, r)
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
            foot.z += offset.y + (leg.name == "leftHind" ? s.hindSplit.x : leg.name == "rightHind" ? s.hindSplit.y : 0)
            p.feet[i] = foot
        }
        // The tail rides high on the move and waves slowly, each joint a little later than the one before; on top of
        // that it swings with the body's turns, starts and landings.
        tailSpring.update(dt, tailPush)
        let tipLift = r * Posture.tipLiftShare(lift: s.lift)
        for i in p.tail.indices {
            let spring = tailSpring.joints[min(i, tailSpring.joints.count - 1)]
            let fi = Float(i)
            p.tail[i].sway = s.sway[min(i, s.sway.count - 1)]
                + lerp((0.06 + 0.05 * fi) * sin(time * 1.6 - fi * 0.8), b.tailSway[i], r)
            p.tail[i].lift = s.tail[min(i, s.tail.count - 1)] + 0.1 * gait.amount + b.tailLift[i] * tipLift + spring.lift
            p.tail[i].lean = spring.lean
        }
        standing.pose = p
        // Hidden, the standing skeleton still poses: the seated head and the tail's swing follow it.
        standing.update(skinning: seatAmount <= 0.5 || mixing != nil)
        tailPush = tailForce(dt)
    }

    /// Poses the seated skeleton: head and ears as the standing one holds them, so the two heads stay on each other
    /// through a swap, `headPitch` being the standing head's own nod without its posture; the tail sweeps along the
    /// floor with the resting behavior. The model-space moves of chest and hips carry over too, shifted into the seated
    /// splat's space.
    private func updateSeat(headPitch: Float) {
        let s = standing.pose
        let b = behavior.state
        var p = seated.pose
        p.headYaw = s.headYaw
        p.headPitch = headPitch
        p.headRoll = s.headRoll
        p.headShift = s.headShift
        p.earLeft = s.earLeft
        p.earRight = s.earRight
        p.earsBack = s.earsBack
        p.earTurnLeft = s.earTurnLeft
        p.earTurnRight = s.earTurnRight
        p.lidLeft = s.lidLeft
        p.lidRight = s.lidRight
        let mount = seated.mount
        func local(_ move: Pose) -> Pose { Pose(q: move.q, t: move.t + move.q.act(mount) - mount) }
        p.chestMove = local(s.chestMove)
        p.hipsMove = local(s.hipsMove)
        let lastJoint = p.tail.count - 1
        for i in p.tail.indices {
            p.tail[i].sway = 1.5 * b.tailSway[i]
            p.tail[i].lift = i == lastJoint ? 0.6 * b.tailLift[i] : 0
        }
        seated.pose = p
        // The seated splat only needs skinning while it shows.
        let body = bodies[rest]
        if (seatAmount > 0.5 || mixing != nil) && body == nil { seated.update() }
        if let body { poseBody(body, like: p) }
    }

    /// Poses a lying splat like the seated one: head and ears do what they do sitting, asleep barely, lids shut in
    /// sleep, the tail only swaying; and settles it in with a short squash after the cut.
    private func poseBody(_ rig: CatRig, like seat: CatRig.Posture) {
        var p = rig.pose
        let still: Float = rest == .sleep ? 0.3 : 1
        p.headYaw = seat.headYaw * still
        p.headPitch = seat.headPitch * still
        p.headRoll = seat.headRoll * still
        p.earLeft = seat.earLeft
        p.earRight = seat.earRight
        p.earsBack = seat.earsBack
        p.earTurnLeft = seat.earTurnLeft
        p.earTurnRight = seat.earTurnRight
        p.lidLeft = rest == .sleep ? 1 : seat.lidLeft
        p.lidRight = rest == .sleep ? 1 : seat.lidRight
        for i in p.tail.indices where i < seat.tail.count { p.tail[i].sway = 0.5 * seat.tail[i].sway }
        rig.pose = p
        let squash = settleTime < 0.45 ? 0.1 * sin(settleTime / 0.45 * .pi) : 0
        rig.entity?.scale = [1 + squash / 2, 1 - squash, 1 + squash / 2]
        if seatAmount > 0.5 { rig.update() }
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

    /// Breath, weight shifts and the chest turning after the head, laid over the body in model space about the seated
    /// spine; the seated skeleton takes the same moves, so the two heads stay on each other.
    private func settle(_ p: inout CatRig.Posture, _ dt: Float, _ r: Float) {
        let b = behavior.state
        breath.update(dt, drowse: behavior.drowse * r, effort: effort)
        let chestYaw = b.chestYaw * r
        // The head keeps looking where it did, the chest having turned under it.
        p.headYaw -= chestYaw
        let lean = Pose.about(floor, .x(-b.forward * r - self.lean.value) * .z(b.lean * r))
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
        let d = standing.neck - standing.spineMid
        p.headPitch += e.pitch
        p.headRoll += e.roll
        p.headShift = [-e.roll * d.y, e.y - e.pitch * d.z, e.pitch * d.y]
    }

    // MARK: - Trips

    private func add(_ duration: Float, _ run: @escaping (Float) -> Void) {
        steps.append(Step(duration: duration, run: run))
    }

    private func add(until done: @escaping (Float) -> Bool, toward target: SIMD3<Float>? = nil, chase: Bool = false) {
        steps.append(Step(duration: .infinity, run: { _ in }, open: done, target: target, chase: chase))
    }

    /// A jump she turns to and sizes up from where she stands; a walk she steers into as she goes.
    private func leg(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ move: Waypoint.Move) {
        if move == .jump {
            turn(facing(to.x - from.x, to.z - from.z))
            jump(from, to)
        } else {
            walk(from, to)
        }
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

    /// From the seated splat to the standing one crouched in its silhouette, then up; or up from a loaf.
    private func standUp() {
        if lying {
            lying = false
            add(0.9) { [unowned self] u in posture = .blend(.loaf, .stand, ease(u)) }
            return
        }
        guard seatAmount > 0.5 else { return }
        // She gathers herself on the seated splat, and the standing one takes over at the bottom of it.
        add(0.3) { [unowned self] u in
            lean.goal = Posture.swapLean
            squash.goal = Self.swapSquash * smoothstep(u, 0.4, 1)
        }
        var time: Float?
        add { [unowned self] dt in
            guard let t = time else {
                time = dt
                swap(seated: false)
                squash.goal = 0
                lean.goal = 0
                change = Change(from: .sit, to: .stand, order: .rising, duration: pace.standUp)
                return false
            }
            time = t + dt
            // Setting off on foot she takes her first steps while her rump is still coming up.
            let walksNext = steps.count > 1 && steps[1].target != nil
            return t + dt >= pace.standUp * (walksNext ? 0.6 : 1)
        }
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

    /// From sitting down into a loaf on the standing splat.
    private func lieDown() {
        add(0.05) { [unowned self] u in fade(1 - u) }
        add(1.4) { [unowned self] u in posture = .blend(.sit, .loaf, ease(u)) }
        add(0.01) { [unowned self] _ in lying = true }
    }

    private func getUp() {
        lying = false
        add(1) { [unowned self] u in posture = .blend(.loaf, .sit, ease(u)) }
        add(0.05) { [unowned self] u in fade(u) }
    }

    private func sitDown() {
        var started = false
        add(pace.sitDown) { [unowned self] u in
            if !started {
                started = true
                change = Change(from: posture, to: .sit, order: .sitting, duration: pace.sitDown)
            }
            // Her rump meets the floor in a squash, and the seated splat takes over at the bottom of it.
            lean.goal = Posture.swapLean * smoothstep(u, 0.3, 0.8)
            squash.goal = Self.swapSquash * smoothstep(u, 0.82, 1)
            if u >= 1 {
                swap(seated: true)
                squash.goal = 0
                lean.goal = 0
            }
        }
    }

    /// Turns on the spot at her pace's rate, the head ahead of the body, with small steps unless the turn is slight.
    private func turn(_ target: Float) {
        planYaw = shortest(planYaw, target)
        var plan: (from: Float, to: Float, duration: Float, time: Float)?
        add { [unowned self] dt in
            var p = plan ?? (yaw, shortest(yaw, target), 0, 0)
            let angle = abs(p.to - p.from)
            guard angle >= 0.01 else { return true }
            if plan == nil { p.duration = 0.15 + angle / pace.turnRate }
            p.time += dt
            plan = p
            let u = min(p.time / p.duration, 1)
            yaw = lerp(p.from, p.to, ease(u))
            lead = min(max(0.8 * (p.to - yaw), -0.45), 0.45)
            stepping = angle > 0.2
            return u >= 1
        }
    }

    /// Walks to `to`, steering: she looks where she is going before she turns, turns as she walks, slower the
    /// further she has to come round, rounds the corner into a next leg instead of stopping at it, and comes to a
    /// stop at the last one over about a stride. Her pace wanders a little as she goes.
    private func walk(_ from: SIMD3<Float>, _ to: SIMD3<Float>, chase: Bool = false) {
        let length = simd_distance(SIMD2(from.x, from.z), SIMD2(to.x, to.z))
        guard simd_distance(from, to) > 0 else { return }
        planYaw = facing(to.x - from.x, to.z - from.z)
        var looked: Float?
        var time: Float = 0
        add(until: { [unowned self] dt in
            let here = group.position
            let ahead = SIMD2(to.x - here.x, to.z - here.z)
            let left = simd_length(ahead)
            let next = steps.count > 1 ? steps[1].target : nil
            time += dt
            // A walk that cannot end (she was moved, or the numbers went wrong) ends where it was going.
            guard length > 1e-4, time < 6 + 4 * length / pace.walkSpeed else {
                group.position = to
                travel = (0, Glide(value: 0))
                return true
            }
            if next != nil, left < Self.cornerCut { return true }
            let heading = left > 0.012 ? facing(ahead.x, ahead.y) : yaw
            let error = shortest(yaw, heading) - yaw
            lead = min(max(0.7 * error, -0.45), 0.45)
            gaze = -0.15
            // From standing, facing well away from where she is going, her head goes there first.
            if looked == nil { looked = !chase && travel.speed < 1e-3 && abs(error) > 0.5 ? 0 : 1 }
            if let l = looked, l < 0.28 {
                looked = l + dt
                return false
            }
            stepping = true

            // Chasing she runs while there is far to go, and is back at a walk a stride or two from the end.
            let rest = chase ? left + self.steps.dropFirst().reduce(0) { $0 + ($1.chase ? 0.1 : 0) } : 0
            let hurry = lerp(1, Self.dash, smoothstep(rest, 0.08, 0.3))
            let cruise = pace.walkSpeed * hurry * (1 + 0.08 * noise(self.time * 0.35, 21))
            let facingIt = max(cos(error), 0)
            var goal = cruise * (0.2 + 0.8 * facingIt * facingIt)
            // No faster than lets her come round to the point at her turning rate.
            goal = min(goal, pace.turnRate * left / max(2 * abs(sin(error)), 0.2))
            let gain = pace.walkSpeed * hurry / pace.rampTime
            if let next {
                // Into a corner she slows by how sharp it is.
                let after = shortest(heading, facing(next.x - to.x, next.z - to.z)) - heading
                let through = cruise * (0.3 + 0.7 * pow(max(cos(after / 2), 0), 2))
                goal = min(goal, sqrt(through * through + 2 * gain * max(left - Self.cornerCut, 0)))
            } else {
                // Never so slow that she creeps up on the point without reaching it.
                goal = max(min(goal, sqrt(2 * gain * left)), 0.015)
            }
            travel.speed += min(max(goal - travel.speed, -2 * gain * dt), gain * dt)
            let turnGoal = min(max(3.5 * error, -pace.turnRate), pace.turnRate)
            travel.turn.follow(turnGoal, rate: 11, dt)
            yaw += travel.turn.value * dt

            let stride = travel.speed * dt
            guard next != nil || stride < left else {
                group.position = to
                travel = (0, Glide(value: 0))
                return true
            }
            // Over the last centimetre she goes straight for the point, so she ends on it.
            let along = left > 0.012 ? SIMD2(-sin(yaw), -cos(yaw)) : ahead / left
            var at = here + SIMD3(along.x, 0, along.y) * stride
            at.y = to.y + (from.y - to.y) * min(simd_distance(SIMD2(at.x, at.z), SIMD2(to.x, to.z)) / length, 1)
            group.position = at
            return false
        }, toward: to, chase: chase)
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
        let air = (0.28 + 0.6 * sqrt(reach)) * pace.flight
        // Room units above the straight line from takeoff to landing.
        let arc = 0.03 + 0.4 * max(0, to.y - from.y)
        let aim = min(max(atan2(rise, hypot(to.x - from.x, to.z - from.z) / scale), -0.6), 0.6)
        func key(_ change: (inout Posture) -> Void) -> Posture {
            var p = Posture.stand
            change(&p)
            return p
        }

        let wiggleTime = Float.random(in: pace.wiggle)
        let gather = key {
            $0.lift = -0.022; $0.back = 0.008; $0.pitch = lerp(-0.1, 0.08, up); $0.bend = 0.05; $0.headPitch = aim * 0.9
            $0.tail = [-0.3, -0.1, 0.1]
        }
        var coil = gather
        coil.lift = -0.032
        coil.back = 0.012
        let gatherTime = pace.gather
        let wiggleRate = pace.wiggleRate
        let prepare = gatherTime + wiggleTime + pace.poise
        add(prepare) { [unowned self] u in
            let t = u * prepare
            group.position = from
            keyframes([(0, .stand), (gatherTime, gather), (gatherTime + wiggleTime, coil)], t)
            // The rump sways side to side, the hind paws treading in turn, then she goes still.
            let w = min(max((t - gatherTime) / wiggleTime, 0), 1)
            let sway = sin(w * .pi) * sin((t - gatherTime) * .pi * 2 * wiggleRate)
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
        add(0.55 * pace.flight) { [unowned self] u in
            group.position = to
            free = true
            keyframes([(0, contact), (0.1, forward), (0.24, settle), (0.55, .stand)], u * 0.55)
        }
    }
}
