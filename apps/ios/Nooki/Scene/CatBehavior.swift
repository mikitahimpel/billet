import Foundation
import simd

private func random(_ low: Float, _ high: Float) -> Float { .random(in: low..<high) }
nonisolated private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// 0 → 1 → 0 over `length` seconds from `start`, 0 outside.
private func bump(_ t: Float, _ start: Float, _ length: Float) -> Float {
    t > start && t < start + length ? sin((t - start) / length * .pi) : 0
}

/// 0 → 1 over the first half second from `start`, held, back to 0 over the last half second of `length`.
private func hold(_ t: Float, _ start: Float, _ length: Float) -> Float {
    smoothstep(t - start, 0, 0.5) * (1 - smoothstep(t - start, length - 0.5, length))
}

/// A blink `u` seconds in: shut in 70 ms, held 40, open again in 150.
private func blinkShape(_ u: Float) -> Float {
    u < 0.07 ? u / 0.07 : u < 0.11 ? 1 : max(0, 1 - (u - 0.11) / 0.15)
}

nonisolated private func hash(_ i: Int) -> Float {
    var h = UInt32(truncatingIfNeeded: i) ^ 0x9e37_79b9
    h = h &* 0x85eb_ca6b
    h ^= h >> 13
    h = h &* 0xc2b2_ae35
    h ^= h >> 16
    return Float(h) / 4_294_967_296
}

/// Smooth gradient noise, about -1 to 1, bending about once per unit of `x`; each `seed` is another curve.
nonisolated func noise(_ x: Float, _ seed: Int = 0) -> Float {
    let i = Int(x.rounded(.down))
    let f = x - Float(i)
    let a = (hash(i + seed * 7919) * 2 - 1) * f
    let b = (hash(i + 1 + seed * 7919) * 2 - 1) * (f - 1)
    return 2 * lerp(a, b, f * f * f * (f * (f * 6 - 15) + 10))
}

/// Moves `value` toward `goal` as a spring of angular frequency `w` and damping ratio `zeta`, in 120 Hz substeps.
private func spring(_ value: inout Float, _ speed: inout Float, _ goal: Float, _ w: Float, _ zeta: Float, _ dt: Float) {
    let n = max(1, Int((dt * 120).rounded(.up)))
    let h = dt / Float(n)
    for _ in 0..<n {
        speed += (w * w * (goal - value) - 2 * zeta * w * speed) * h
        value += speed * h
    }
}

/// What Mochi does sitting, ported from nooki-scene/src/three/catRig.js: glances around with her eyes first and her
/// head snapping after, overshooting a little and holding; follows a finger dragged across the screen, checks on
/// whoever watches, twitches and swivels her ears toward sounds only she hears, yawns, washes her chest, waves and
/// flicks her tail, blinks every few seconds and with big turns of her head, leans into a pet with ears back and eyes
/// narrowed, looks up and slow-blinks after it, and gets drowsy when tired. Her ears are springs that lag her head.
/// A mood drives all of it: `energy` drains at rest and makes her drowsy when low, `interest` rises with anything going
/// on and makes her quick and alert, `contentment` grows with pets and softens her eyes and tail.
final class CatBehavior {
    private struct Sound {
        let start: Float
        let yaw: Float
        let length: Float
        let look: Bool
    }

    struct Values {
        var lean: Float = 0, forward: Float = 0, chestYaw: Float = 0
        var yaw: Float = 0, pitch: Float = 0, roll: Float = 0
        var earLeft: Float = 0, earRight: Float = 0, earsBack: Float = 0, earTurnLeft: Float = 0, earTurnRight: Float = 0
        var lidLeft: Float = 0, lidRight: Float = 0
        var tailSway: [Float], tailLift: [Float]
    }

    struct Mood {
        var energy: Float = 0.7, interest: Float = 0.3, contentment: Float = 0.5
    }

    private let tailCount: Int
    private var time: Float = 0
    private var lookTarget: SIMD3<Float>?
    private var viewer: SIMD3<Float>?
    private var lastPointer: Float = -10
    private var pointerSince: Float = -10
    private var petStart: Float = -10
    private var nextGlance: Float = 1
    private var glance: (yaw: Float, pitch: Float, roll: Float) = (0, 0, 0)
    private var nextTwitch: Float = 2
    private var twitch: (start: Float, left: Bool, both: Bool)?
    // Where the head is headed (the eyes are already there), and since when.
    private var aim: (yaw: Float, pitch: Float, time: Float, turn: Float) = (0, 0, 0, 0)
    private var speed = Values(tailSway: [], tailLift: [])
    private var nextSound = random(4, 12)
    private var sound: Sound?
    private var nextYawn = random(25, 60)
    private var yawnStart: Float = -10
    private var nextFlick = random(6, 14)
    private var flick: (start: Float, curl: Bool, side: Float)?
    private var nextBlink = random(1, 4)
    private var blinks: [Float] = []
    private var nextSlowBlink: Float = 0
    private var slowBlink: Float = -10
    private var nextContentBlink = random(8, 16)
    private var nextShift = random(10, 20)
    private var shift: (lean: Float, forward: Float) = (0, 0)
    private var nextCheck = random(5, 12)
    private var check: (start: Float, length: Float)?
    private var nextGroom = random(30, 60)
    private var groom: (start: Float, length: Float, side: Float)?
    private var tailPhase: Float = 0
    private(set) var mood = Mood()
    /// Set by whoever moves her: asleep in a loaf, she gets her energy back.
    var napping = false
    /// Set when a brain decides how sleepy she is and when she yawns and grooms, in place of her own timers.
    var directed = false
    /// How sleepy the brain says she is, from 0 awake to 1 asleep; she eases into it.
    var sleepiness: Float = 0
    private var sleepy: Float = 0
    /// A heading for her glances to favour, relative to her body, or nil to look about freely.
    var focus: Float?
    private(set) var drowse: Float = 0
    private(set) var blink: Float = 0
    private(set) var state: Values
    private var target: Values

    init(tailJoints: Int) {
        tailCount = tailJoints
        state = Values(tailSway: Array(repeating: 0, count: tailJoints), tailLift: Array(repeating: 0, count: tailJoints))
        target = state
    }

    /// Point in the cat's model space to look at, such as under a dragged finger, or nil once it lifts.
    func lookAt(_ point: SIMD3<Float>?) {
        lookTarget = point
        if point != nil && time - lastPointer > 2 { pointerSince = time }
        if point != nil { lastPointer = time }
    }

    /// Where whoever watches her is, in the cat's model space: the camera.
    func watch(_ point: SIMD3<Float>) {
        viewer = point
    }

    func pet() {
        petStart = time
        stir(0.25)
    }

    /// Wakes her up by `amount` of her energy.
    func stir(_ amount: Float) {
        mood.energy = min(1, mood.energy + amount)
    }

    /// Something she can be asked to do right away, to show each of her habits in turn.
    enum Act {
        case twitch, listen, slowBlink, yawn, flick, curl, groom
        /// Her head shakes off a pounce: quick turns left and right, ears flapping.
        case shake
        /// The head tips over to one side, ears forward, and holds.
        case tilt
        /// The head bobs quickly and the tail tip twitches, at a bird behind the glass.
        case chatter
        /// The head follows something quick, from one side to the other.
        case track
        /// The head comes up and follows something small in the air.
        case lookUp
        /// Dozes off for `seconds`: lids shut, head sinks, ears spread.
        case doze(Float)
    }

    func perform(_ act: Act) {
        let t = time
        switch act {
        case .twitch: twitch = (t, Bool.random(), false)
        case .listen: sound = Sound(start: t, yaw: Bool.random() ? -2 : 2, length: 1.6, look: true)
        case .slowBlink: slowBlink = t
        case .yawn: yawnStart = t
        case .flick: flick = (t, false, Bool.random() ? -1 : 1)
        case .curl: flick = (t, true, 1)
        case .groom: groom = (t, 5, Bool.random() ? -1 : 1)
        case .doze(let seconds): doze = (t, seconds)
        case .shake: gesture = (.shake, t, Bool.random() ? -1 : 1)
        case .tilt: gesture = (.tilt, t, Bool.random() ? -1 : 1)
        case .chatter: gesture = (.chatter, t, Bool.random() ? -1 : 1)
        case .track: gesture = (.track, t, Bool.random() ? -1 : 1)
        case .lookUp: gesture = (.lookUp, t, Bool.random() ? -1 : 1)
        }
    }

    private var gesture: (kind: Act, start: Float, side: Float)?

    /// What the current gesture adds to the head and ears at `t`: yaw, pitch, roll, both ears forward, the tail tip.
    private func gestureOffsets(_ t: Float) -> (yaw: Float, pitch: Float, roll: Float, ears: Float, tip: Float) {
        guard let gesture else { return (0, 0, 0, 0, 0) }
        let u = t - gesture.start
        switch gesture.kind {
        case .shake:
            let fade = max(0, 1 - u / 0.9)
            return (0.4 * sin(u * 34) * fade, 0, 0.1 * sin(u * 34 + 1) * fade, 0.5 * abs(sin(u * 34)) * fade, 0)
        case .tilt:
            let h = hold(t, gesture.start, 2.4)
            return (0, 0.04 * h, 0.38 * gesture.side * h, -0.2 * h, 0)
        case .chatter:
            let h = hold(t, gesture.start, 3)
            return (0, 0.14 * h + 0.05 * h * sin(u * 38), 0, -0.25 * h, 0.5 * h * sin(u * 17))
        case .track:
            let h = hold(t, gesture.start, 3.6)
            return (gesture.side * 0.55 * h * cos(u / 3.6 * .pi), 0.05 * h, 0, -0.2 * h, 0)
        case .lookUp:
            let h = hold(t, gesture.start, 4)
            return (0.25 * gesture.side * h * sin(u * 1.4), 0.3 * h, 0, -0.2 * h, 0)
        case .twitch, .listen, .slowBlink, .yawn, .flick, .curl, .groom, .doze:
            return (0, 0, 0, 0, 0)
        }
    }

    private var doze: (start: Float, length: Float)?

    /// Yaw and pitch of a model-space point seen from `eyes`.
    private func toward(_ point: SIMD3<Float>, from eyes: SIMD3<Float>) -> (yaw: Float, pitch: Float) {
        let d = point - eyes
        return (atan2(-d.x, -d.z), atan2(d.y, hypot(d.x, d.z)))
    }

    /// `eyes`: the model-space point between her eyes as posed last frame.
    func update(_ dt: Float, eyes: SIMD3<Float>) {
        time += dt
        let t = time
        let left = t - max(lastPointer, petStart)
        let near: Float = lookTarget != nil && t - lastPointer < 2 ? 1 : 0

        // Idle glances: every few seconds a new direction, sometimes with a curious head tilt; livelier, she glances
        // more often and wider.
        if t > nextGlance {
            let reach = 0.6 + 0.6 * mood.energy
            let toward = focus.flatMap { Float.random(in: 0..<1) < 0.7 ? $0 + random(-0.12, 0.12) : nil }
            glance = (toward ?? random(-0.45, 0.45) * reach, random(-0.075, 0.175),
                      Float.random(in: 0..<1) < 0.3 ? random(-0.25, 0.25) : 0)
            nextGlance = t + random(2, 5) * lerp(1.8, 0.8, mood.energy) * (1 - 0.4 * mood.interest)
        }
        var (yaw, pitch, roll) = glance

        // A sound off to one side or behind: the ear on that side swivels to it, and now and then she looks.
        if t > nextSound {
            sound = Sound(start: t, yaw: random(-2.5, 2.5), length: random(0.8, 1.8), look: Float.random(in: 0..<1) < 0.3)
            if sound?.look == true { stir(0.08) }
            nextSound = t + random(6, 16)
        }
        let heard = sound.map { sqrt(bump(t, $0.start, $0.length)) } ?? 0
        if let sound, sound.look, t > sound.start + 0.25, t < sound.start + sound.length + 0.8 {
            (yaw, pitch, roll) = (sound.yaw, 0, 0)
        }

        // Now and then she checks on whoever watches, more often when curious, and slow-blinks at them when content;
        // right after a pet she looks up at them.
        if t > nextCheck {
            if viewer != nil && Float.random(in: 0..<1) < 0.3 + 0.5 * mood.interest {
                check = (t, random(1.2, 2.6))
                if mood.contentment > 0.55 { slowBlink = t + 0.5 }
            }
            nextCheck = t + random(6, 14)
        }
        let p = t - petStart
        let checking: Float = check.map { t < $0.start + $0.length } == true ? 1 : 0
        if let viewer, checking > 0 || (p > 0.4 && p < 3.6) {
            let at = toward(viewer, from: eyes)
            if abs(at.yaw) < 1.2 { (yaw, pitch, roll) = (at.yaw, at.pitch, 0) }
        }
        if near > 0, let lookTarget {
            let at = toward(lookTarget, from: eyes)
            (yaw, pitch, roll) = (at.yaw, at.pitch, 0)
        }
        // The neck turns only so far before the blend band shears.
        yaw = min(max(yaw, -0.6), 0.6)
        pitch = min(max(pitch, -0.25), 0.3)

        // The eyes are on (yaw, pitch) at once; the head re-aims once they are far enough off it or have rested there,
        // in smaller steps while following a finger.
        let off = hypot(yaw - aim.yaw, pitch - aim.pitch)
        if off > (near > 0 ? 0.06 : 0.12) || (off > 0.03 && t - aim.time > 0.5) {
            aim = (yaw, pitch, t, yaw - aim.yaw)
        }

        // Yawn: the head tips back and over with the ears folding, then comes back; tired, she yawns more.
        if t > nextYawn {
            if left > 4 && !directed { yawnStart = t }
            nextYawn = t + random(40, 90) * lerp(0.6, 1.4, mood.energy)
        }
        let yawn = pow(bump(t, yawnStart, 2.4), 1.5)

        // Energy drains at rest and comes back with a nap; low, it makes her drowsy, unless something is going on.
        mood.energy = min(max(mood.energy + dt * (napping ? 1 / 200 : -1 / 150), 0), 1)
        sleepy += (sleepiness - sleepy) * (1 - exp(-dt * 0.8))
        let tired = directed ? min(sleepy, 0.85) : 1 - smoothstep(mood.energy, 0.1, 0.35)
        var drowse = tired * (1 - heard) * (1 - near)
        if let doze {
            let u = t - doze.start
            drowse = max(drowse, smoothstep(u, 0, 1.5) * (1 - smoothstep(u, doze.length - 1, doze.length)))
        }
        self.drowse = drowse
        let dozing = doze.map { smoothstep(t - $0.start, 1, 2.5) * (1 - smoothstep(t - $0.start, $0.length - 1.2, $0.length)) } ?? 0
        let asleep = max(dozing, directed ? smoothstep(sleepy, 0.7, 0.95) : 0)

        // Every 10-20 s she settles her weight a little differently, leaning to a side or forward, and holds it; her chest
        // turns a little after her head.
        if t > nextShift {
            shift = (random(-0.025, 0.025), random(-0.01, 0.02))
            nextShift = t + random(10, 20)
        }
        target.lean = shift.lean
        target.forward = shift.forward
        target.chestYaw = 0.13 * state.yaw

        // Petting: lean into the hand, ears back, tail tip up, for about two seconds.
        let petting = p < 2 ? sin(min(p / 0.3, 1) * .pi / 2) * (1 - smoothstep(p, 1.5, 2)) : 0

        // Grooming: every minute or so, awake and left alone, she washes her chest in short licks, head down and to a
        // side, eyes half shut.
        if t > nextGroom {
            if left > 8 && drowse < 0.3 && !directed { groom = (t, random(3, 5.5), Bool.random() ? -1 : 1) }
            nextGroom = t + random(40, 90)
        }
        let washing = groom.map { near > 0 ? 0 : hold(t, $0.start, $0.length) } ?? 0
        let lick = washing * max(0, sin((t - (groom?.start ?? 0)) * .pi * 2 * 2.8))
        let side = groom?.side ?? 0

        let free = (1 - petting) * (1 - yawn) * (1 - washing)
        let behind = smoothstep(abs(sound?.yaw ?? 0), 1.2, 2.2)
        // Holding still, the head still drifts a hair.
        target.yaw = aim.yaw * free * (1 - asleep) + 0.45 * side * washing + 0.012 * noise(t * 0.7, 1)
        target.pitch = aim.pitch * free * (1 - asleep) + 0.12 * petting + 0.3 * yawn - 0.12 * drowse - 0.18 * asleep
            + washing * (0.07 * lick - 0.45) + 0.01 * noise(t * 0.7, 2)
        target.roll = roll * free + 0.32 * petting * sin(p * 3) + 0.2 * yawn + 0.2 * side * washing
        target.earsBack = 0.5 * petting + 0.35 * yawn + 0.25 * heard * behind + 0.15 * washing
        let move = gestureOffsets(t)
        target.yaw += move.yaw
        target.pitch += move.pitch
        target.roll += move.roll
        target.earsBack += move.ears

        // Interest jumps with anything going on and fades over several seconds; contentment grows with pets and slowly
        // settles back.
        let lure = max(near, heard, 0.6 * petting, 0.5 * checking)
        mood.interest += (lure - mood.interest) * (1 - exp(-dt * (lure > mood.interest ? 3 : 1 / 8)))
        mood.contentment = min(max(mood.contentment + dt * (0.25 * petting + (0.4 - mood.contentment) / 120), 0), 1)

        // Ear twitches: one ear, quick flick out and back; more of them when she is curious.
        if t > nextTwitch {
            twitch = (t, Bool.random(), Float.random(in: 0..<1) < 0.25)
            nextTwitch = t + random(2.5, 6.5) * (1.3 - 0.6 * mood.interest)
        }
        target.earLeft = 0
        target.earRight = 0
        if let twitch {
            let q = (t - twitch.start) / 0.35
            let amount: Float = q < 1 ? sin(q * .pi) * 0.45 : 0
            if twitch.both || twitch.left { target.earLeft = amount }
            if twitch.both || !twitch.left { target.earRight = amount }
        }
        // An ear swings ahead of the head toward where it turns (negative yaw is her left), and both lag the turn itself,
        // one flaring as the other folds.
        let lead: Float = abs(aim.turn) > 0.2 ? 0.3 * bump(t, aim.time, 0.45) : 0
        if aim.turn < 0 { target.earLeft += lead } else { target.earRight += lead }
        target.earLeft += 0.03 * speed.yaw
        target.earRight -= 0.03 * speed.yaw

        // Ears drift on their own, each its own way; the one on a sound's side swings its opening round to it, the other
        // following for a sound behind her. They point at the finger, forward when she is curious, and spread out while
        // petted, drowsy or content.
        func swivel(_ seed: Int, towards: Bool) -> Float {
            0.14 * noise(t * 0.3, seed) * (1 - near)
                + heard * (towards ? 0.5 + 0.6 * behind : 0.4 * behind) - 0.2 * near + 0.45 * petting + 0.25 * drowse
                - 0.15 * mood.interest + 0.1 * mood.contentment
        }
        target.earTurnLeft = swivel(10, towards: sound.map { $0.yaw < 0 } ?? false)
        target.earTurnRight = swivel(11, towards: sound.map { $0.yaw >= 0 } ?? false)

        // Eyes: quick blinks, sometimes doubled, fewer when curious; half shut while petted or washing; a slow blink back
        // at someone who has lingered a few seconds, after a pet, and now and then when content; heavy lids when drowsy,
        // soft ones when content, and shut through a yawn.
        if t > nextBlink || (aim.time == t && abs(aim.turn) > 0.35) {
            blinks.append(t)
            if Float.random(in: 0..<1) < 0.2 { blinks.append(t + 0.3) }
            nextBlink = t + random(2.5, 7) * (1 + 1.5 * drowse) * (1 + 0.5 * mood.interest)
        }
        blinks.removeAll { t - $0 >= 0.3 }
        blink = blinks.map { t >= $0 ? blinkShape(t - $0) : 0 }.max() ?? 0
        if near > 0 && t - pointerSince > 3 && t > nextSlowBlink {
            slowBlink = t
            nextSlowBlink = t + random(6, 12)
        }
        if p > 2.2 && p - dt <= 2.2 { slowBlink = t }
        if t > nextContentBlink {
            if mood.contentment > 0.6 && near == 0 { slowBlink = t }
            nextContentBlink = t + random(8, 18)
        }
        let slow = min(smoothstep(t - slowBlink, 0, 0.5), 1 - smoothstep(t - slowBlink, 1.1, 1.8))
        let lid = max(0.55 * petting, 0.85 * slow, 0.9 * yawn, drowse * (0.6 + 0.1 * noise(t * 0.3, 3)), asleep,
                      0.5 * washing, 0.15 * mood.contentment * (1 - mood.interest))
        target.lidLeft = lid
        target.lidRight = lid * (1 - 0.08 * drowse)

        // Tail: a wave runs from the base to the tip, each joint a little later and wider than the last, its pace and
        // size wandering; calmer when she is content, quicker when curious, the tip twitching then. Now and then the tip
        // lifts, and it stays up while petted. Left alone, she flicks the tip sideways or curls it up for a while.
        tailPhase += dt * 0.9 * (1 + 0.35 * noise(t * 0.15, 4)) * (1 + 0.5 * mood.interest)
        let swing = (1.3 - 0.6 * mood.contentment) * (1 + 0.3 * noise(t * 0.2, 5))
        let tipUp = pow(max(0, noise(t * 0.35, 6)), 3)
        for i in 0..<tailCount {
            let share = Float(i) / Float(max(tailCount - 1, 1))
            let wave = sin(tailPhase - Float(i) * 0.7) + 0.3 * sin(tailPhase * 2.6 - Float(i))
            target.tailSway[i] = (0.04 + 0.08 * share) * swing * wave
            target.tailLift[i] = 0.25 * share * share * (tipUp + 1.2 * petting)
        }
        if t > nextFlick {
            if left > 12 { flick = (t, Float.random(in: 0..<1) < 0.35, Bool.random() ? -1 : 1) }
            nextFlick = t + random(9, 20)
        }
        let last = tailCount - 1
        if last >= 0 { target.tailSway[last] += 0.12 * mood.interest * noise(t * 2.5, 7) }
        if last >= 0 { target.tailSway[last] += move.tip }
        if let flick, last >= 0 {
            if flick.curl { target.tailLift[last] += 0.5 * bump(t, flick.start, 3) }
            else { target.tailSway[last] += 0.5 * flick.side * bump(t, flick.start, 0.35) }
        }

        // The head snaps after the eyes as a lightly damped spring, overshooting a little before it holds; the ears are
        // looser springs still. The rest eases, tail lifts quicker, the body's weight slowly.
        spring(&state.yaw, &speed.yaw, target.yaw, 11, 0.6, dt)
        spring(&state.pitch, &speed.pitch, target.pitch, 11, 0.6, dt)
        spring(&state.earLeft, &speed.earLeft, target.earLeft, 20, 0.35, dt)
        spring(&state.earRight, &speed.earRight, target.earRight, 20, 0.35, dt)
        spring(&state.earsBack, &speed.earsBack, target.earsBack, 20, 0.35, dt)
        spring(&state.earTurnLeft, &speed.earTurnLeft, target.earTurnLeft, 20, 0.35, dt)
        spring(&state.earTurnRight, &speed.earTurnRight, target.earTurnRight, 20, 0.35, dt)
        let k = 1 - exp(-dt * 7)
        let fast = 1 - exp(-dt * 20)
        func ease(_ value: inout Float, _ goal: Float, _ rate: Float) { value += (goal - value) * rate }
        let settle = 1 - exp(-dt * 1.2)
        ease(&state.lean, target.lean, settle)
        ease(&state.forward, target.forward, settle)
        ease(&state.chestYaw, target.chestYaw, 1 - exp(-dt * 2))
        ease(&state.roll, target.roll, k)
        ease(&state.lidLeft, target.lidLeft, k)
        ease(&state.lidRight, target.lidRight, k)
        for i in 0..<tailCount {
            ease(&state.tailSway[i], target.tailSway[i], k)
            ease(&state.tailLift[i], target.tailLift[i], fast)
        }
    }
}
