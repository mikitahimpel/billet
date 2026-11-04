import Foundation

private func random(_ low: Float, _ high: Float) -> Float { .random(in: low..<high) }

/// 0 → 1 → 0 over `length` seconds from `start`, 0 outside.
private func bump(_ t: Float, _ start: Float, _ length: Float) -> Float {
    t > start && t < start + length ? sin((t - start) / length * .pi) : 0
}

/// A blink `u` seconds in: shut in 70 ms, held 40, open again in 150.
private func blinkShape(_ u: Float) -> Float {
    u < 0.07 ? u / 0.07 : u < 0.11 ? 1 : max(0, 1 - (u - 0.11) / 0.15)
}

/// What Mochi does sitting, ported from nooki-scene/src/three/catRig.js: glances around with her eyes first and her
/// head after, twitches and swivels her ears toward sounds only she hears, yawns, waves and flicks her tail, blinks every
/// few seconds and with big turns of her head, leans into a pet with ears back and eyes narrowed, slow-blinks after it,
/// and gets drowsy when left alone.
/// note: the web cat also follows the pointer and slow-blinks at it; there is no hover on a phone, so that is left out.
final class CatBehavior {
    private struct Sound {
        let start: Float
        let yaw: Float
        let length: Float
        let look: Bool
    }

    struct Values {
        var yaw: Float = 0, pitch: Float = 0, roll: Float = 0
        var earLeft: Float = 0, earRight: Float = 0, earsBack: Float = 0, earTurnLeft: Float = 0, earTurnRight: Float = 0
        var lidLeft: Float = 0, lidRight: Float = 0
        var tailSway: [Float], tailLift: [Float]
    }

    private let tailCount: Int
    private var time: Float = 0
    private var petStart: Float = -10
    private var nextGlance: Float = 1
    private var glance: (yaw: Float, pitch: Float, roll: Float) = (0, 0, 0)
    private var nextTwitch: Float = 2
    private var twitch: (start: Float, left: Bool, both: Bool)?
    // Where the head is headed (the eyes are already there), and since when.
    private var aim: (yaw: Float, pitch: Float, time: Float, turn: Float) = (0, 0, 0, 0)
    private var turnSpeed: (yaw: Float, pitch: Float) = (0, 0)
    private var nextSound = random(4, 12)
    private var sound: Sound?
    private var nextYawn = random(25, 60)
    private var yawnStart: Float = -10
    private var nextFlick = random(6, 14)
    private var flick: (start: Float, curl: Bool, side: Float)?
    private var nextBlink = random(1, 4)
    private var blinks: [Float] = []
    private var slowBlink: Float = -10
    private(set) var blink: Float = 0
    private(set) var state: Values
    private var target: Values

    init(tailJoints: Int) {
        tailCount = tailJoints
        state = Values(tailSway: Array(repeating: 0, count: tailJoints), tailLift: Array(repeating: 0, count: tailJoints))
        target = state
    }

    func pet() {
        petStart = time
    }

    /// Something she can be asked to do right away, to show each of her habits in turn.
    enum Act {
        case twitch, listen, slowBlink, yawn, flick, curl
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
        case .doze(let seconds): doze = (t, seconds)
        }
    }

    private var doze: (start: Float, length: Float)?

    func update(_ dt: Float) {
        time += dt
        let t = time
        let left = t - petStart

        // Idle glances: every few seconds a new direction, sometimes with a curious head tilt.
        if t > nextGlance {
            glance = (random(-0.45, 0.45), random(-0.075, 0.175), Float.random(in: 0..<1) < 0.3 ? random(-0.25, 0.25) : 0)
            nextGlance = t + random(2, 5)
        }
        var (yaw, pitch, roll) = glance

        // A sound off to one side or behind: the ear on that side swivels to it, and now and then she looks.
        if t > nextSound {
            sound = Sound(start: t, yaw: random(-2.5, 2.5), length: random(0.8, 1.8), look: Float.random(in: 0..<1) < 0.3)
            nextSound = t + random(6, 16)
        }
        let heard = sound.map { sqrt(bump(t, $0.start, $0.length)) } ?? 0
        if let sound, sound.look, t > sound.start + 0.25, t < sound.start + sound.length + 0.8 {
            (yaw, pitch, roll) = (sound.yaw, 0, 0)
        }
        // The neck turns only so far before the blend band shears.
        yaw = min(max(yaw, -0.6), 0.6)
        pitch = min(max(pitch, -0.25), 0.3)

        // The eyes are on (yaw, pitch) at once; the head re-aims once they are far enough off it or have rested there.
        let off = hypot(yaw - aim.yaw, pitch - aim.pitch)
        if off > 0.12 || (off > 0.03 && t - aim.time > 0.5) {
            aim = (yaw, pitch, t, yaw - aim.yaw)
        }

        // Yawn: the head tips back and over with the ears folding, then comes back.
        if t > nextYawn {
            if left > 4 { yawnStart = t }
            nextYawn = t + random(40, 90)
        }
        let yawn = pow(bump(t, yawnStart, 2.4), 1.5)
        // Nothing happening for half a minute makes her drowsy; a sound wakes her.
        var drowse = smoothstep(left, 30, 50) * (1 - heard)
        if let doze {
            let u = t - doze.start
            drowse = max(drowse, smoothstep(u, 0, 1.5) * (1 - smoothstep(u, doze.length - 1, doze.length)))
        }
        let asleep = doze.map { smoothstep(t - $0.start, 1, 2.5) * (1 - smoothstep(t - $0.start, $0.length - 1.2, $0.length)) } ?? 0

        // Petting: lean into the hand, ears back, tail tip up, for about two seconds.
        let p = t - petStart
        let petting = p < 2 ? sin(min(p / 0.3, 1) * .pi / 2) * (1 - smoothstep(p, 1.5, 2)) : 0
        let free = (1 - petting) * (1 - yawn)
        let behind = smoothstep(abs(sound?.yaw ?? 0), 1.2, 2.2)
        target.yaw = aim.yaw * free * (1 - asleep)
        target.pitch = aim.pitch * free * (1 - asleep) + 0.12 * petting + 0.3 * yawn - 0.12 * drowse - 0.18 * asleep
        target.roll = roll * free + 0.32 * petting * sin(p * 3) + 0.2 * yawn
        target.earsBack = 0.5 * petting + 0.35 * yawn + 0.25 * heard * behind

        // Ear twitches: one ear, quick flick out and back.
        if t > nextTwitch {
            twitch = (t, Bool.random(), Float.random(in: 0..<1) < 0.25)
            nextTwitch = t + random(2.5, 6.5)
        }
        target.earLeft = 0
        target.earRight = 0
        if let twitch {
            let q = (t - twitch.start) / 0.35
            let amount: Float = q < 1 ? sin(q * .pi) * 0.45 : 0
            if twitch.both || twitch.left { target.earLeft = amount }
            if twitch.both || !twitch.left { target.earRight = amount }
        }
        // An ear swings ahead of the head toward where it turns (negative yaw is her left).
        let lead: Float = abs(aim.turn) > 0.2 ? 0.3 * bump(t, aim.time, 0.45) : 0
        if aim.turn < 0 { target.earLeft += lead } else { target.earRight += lead }

        // Ears drift on their own, each at its own pace; the one on a sound's side swings its opening round to it, the
        // other following for a sound behind her. They spread out while petted or drowsy.
        func swivel(_ phase: Float, towards: Bool) -> Float {
            0.1 * sin(t * 0.37 + phase) + 0.06 * sin(t * 1.13 + 2 * phase)
                + heard * (towards ? 0.5 + 0.6 * behind : 0.4 * behind) + 0.45 * petting + 0.25 * drowse
        }
        target.earTurnLeft = swivel(0, towards: sound.map { $0.yaw < 0 } ?? false)
        target.earTurnRight = swivel(2.1, towards: sound.map { $0.yaw >= 0 } ?? false)

        // Eyes: quick blinks, sometimes doubled; half shut while petted; a slow blink right after a pet; heavy lids
        // when drowsy, and shut through a yawn.
        if t > nextBlink || (aim.time == t && abs(aim.turn) > 0.35) {
            blinks.append(t)
            if Float.random(in: 0..<1) < 0.2 { blinks.append(t + 0.3) }
            nextBlink = t + random(2.5, 7) * (1 + 1.5 * drowse)
        }
        blinks.removeAll { t - $0 >= 0.3 }
        blink = blinks.map { blinkShape(t - $0) }.max() ?? 0
        if p > 2.2 && p - dt <= 2.2 { slowBlink = t }
        let slow = min(smoothstep(t - slowBlink, 0, 0.5), 1 - smoothstep(t - slowBlink, 1.1, 1.8))
        let lid = max(0.55 * petting, 0.85 * slow, 0.9 * yawn, drowse * (0.6 + 0.1 * sin(t * 0.4)), asleep)
        target.lidLeft = lid
        target.lidRight = lid * (1 - 0.08 * drowse)

        // Tail: a slow wave runs from the base to the tip, each joint a little later and wider than the last; now and
        // then the tip flicks up, and it stays up while petted. Left alone, she flicks the tip sideways or curls it up.
        let tipUp = pow(max(0, sin(t * 0.7)), 6)
        for i in 0..<tailCount {
            let share = Float(i) / Float(max(tailCount - 1, 1))
            let wave = sin(t * 0.9 - Float(i) * 0.7) + 0.3 * sin(t * 2.3 - Float(i))
            target.tailSway[i] = (0.04 + 0.08 * share) * wave
            target.tailLift[i] = 0.25 * share * share * (tipUp + 1.2 * petting)
        }
        if t > nextFlick {
            if left > 12 { flick = (t, Float.random(in: 0..<1) < 0.35, Bool.random() ? -1 : 1) }
            nextFlick = t + random(9, 20)
        }
        let last = tailCount - 1
        if let flick, last >= 0 {
            if flick.curl { target.tailLift[last] += 0.5 * bump(t, flick.start, 3) }
            else { target.tailSway[last] += 0.5 * flick.side * bump(t, flick.start, 0.35) }
        }

        // The head turns like a critically damped spring, slow to start and soft to stop; the rest eases, ears and tail
        // lift quicker.
        let w: Float = 9
        turnSpeed.yaw += (w * w * (target.yaw - state.yaw) - 2 * w * turnSpeed.yaw) * dt
        turnSpeed.pitch += (w * w * (target.pitch - state.pitch) - 2 * w * turnSpeed.pitch) * dt
        state.yaw += turnSpeed.yaw * dt
        state.pitch += turnSpeed.pitch * dt
        let k = 1 - exp(-dt * 7)
        let fast = 1 - exp(-dt * 20)
        func ease(_ value: inout Float, _ goal: Float, _ rate: Float) { value += (goal - value) * rate }
        ease(&state.roll, target.roll, k)
        ease(&state.lidLeft, target.lidLeft, k)
        ease(&state.lidRight, target.lidRight, k)
        ease(&state.earLeft, target.earLeft, fast)
        ease(&state.earRight, target.earRight, fast)
        ease(&state.earsBack, target.earsBack, fast)
        ease(&state.earTurnLeft, target.earTurnLeft, fast)
        ease(&state.earTurnRight, target.earTurnRight, fast)
        for i in 0..<tailCount {
            ease(&state.tailSway[i], target.tailSway[i], k)
            ease(&state.tailLift[i], target.tailLift[i], fast)
        }
    }
}
