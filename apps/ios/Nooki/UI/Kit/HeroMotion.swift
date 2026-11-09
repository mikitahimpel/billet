import Foundation

/// The hero Mochi's pose at one moment: breath from 0 (out) to 1 (in), a slow side-to-side `sway` from -1 to 1 that
/// moves the stage's layers by different amounts, the lids and her ear as baked frames (0 rest, 1 half, 2 full), and
/// `hop` from 0 to 1 after a tap.
nonisolated struct HeroPose: Equatable, Sendable {
    var breath: Double = 0.5
    var sway: Double = 0
    var blink = 0
    var ear = 0
    var hop: Double = 0

    static let rest = HeroPose()
}

/// A loop as data, so the splash and the welcome play the same cat and a test can read it. Blinks and the ear flick
/// keep the room's timing (`CatBehavior`): a lid shuts in 70 ms, holds 40 and opens in 150; an ear goes out and back
/// in 350 ms.
nonisolated enum HeroMotion {
    /// Seconds; the breath and the sway both fit it a whole number of times, so the loop has no seam.
    static let loop: TimeInterval = 9
    static let breathPeriod: TimeInterval = 3
    /// Seconds into the loop; the second blink is doubled, as a cat does now and then.
    static let blinks: [TimeInterval] = [1.4, 4.6, 4.95, 7.6]
    static let flicks: [TimeInterval] = [3.2, 8.1]
    static let hopLength: TimeInterval = 0.45

    static func pose(at time: TimeInterval, pokedAt: TimeInterval? = nil) -> HeroPose {
        let t = time.truncatingRemainder(dividingBy: loop) + (time < 0 ? loop : 0)
        let breath = 0.5 - 0.5 * cos(2 * .pi * t / breathPeriod)
        let sway = sin(2 * .pi * t / loop)
        // Times from the start of every loop that could still be playing, the one before included.
        func since(_ starts: [TimeInterval]) -> [TimeInterval] {
            starts.flatMap { [t - $0, t - $0 + loop] }
        }
        var lids = since(blinks).map(lid).max() ?? 0
        var ear = since(flicks).map(flick).max() ?? 0
        var hop = 0.0
        if let pokedAt, time >= pokedAt {
            let u = time - pokedAt
            lids = max(lids, lid(u))
            ear = max(ear, flick(u - 0.05))
            hop = u < hopLength ? sin(.pi * u / hopLength) : 0
        }
        return HeroPose(breath: breath, sway: sway, blink: frame(lids), ear: frame(ear), hop: hop)
    }

    /// How shut the lids are `u` seconds into a blink, 0 to 1.
    static func lid(_ u: TimeInterval) -> Double {
        switch u {
        case ..<0: 0
        case ..<0.07: u / 0.07
        case ..<0.11: 1
        case ..<0.26: 1 - (u - 0.11) / 0.15
        default: 0
        }
    }

    /// How far out the ear is `u` seconds into a flick, 0 to 1.
    static func flick(_ u: TimeInterval) -> Double {
        u < 0 || u >= 0.35 ? 0 : sin(.pi * u / 0.35)
    }

    /// The baked frame nearest an amount: rest, half, or full.
    static func frame(_ amount: Double) -> Int {
        amount < 0.25 ? 0 : amount < 0.75 ? 1 : 2
    }
}
