import Foundation

/// The welcome screen's whole timeline as data: when each part of the screen comes in. The view only reads it, so the
/// screen plays the same way every time, can be restarted, and jumps to its end with Reduce Motion.
nonisolated struct WelcomeScript: Equatable, Sendable {
    enum Beat: Hashable, Sendable {
        case cat, title, subtitle, vignette(Int), actions
    }

    struct Cue: Equatable, Sendable {
        let beat: Beat
        /// Seconds from the start of the screen to the first frame of the fade-in.
        let start: TimeInterval
        let length: TimeInterval
    }

    let cues: [Cue]

    static let standard = WelcomeScript(cues: [
        Cue(beat: .cat, start: 0, length: 0.5),
        Cue(beat: .title, start: 0.35, length: 0.5),
        Cue(beat: .subtitle, start: 0.7, length: 0.5),
        Cue(beat: .vignette(0), start: 1.1, length: 0.45),
        Cue(beat: .vignette(1), start: 1.45, length: 0.45),
        Cue(beat: .vignette(2), start: 1.8, length: 0.45),
        Cue(beat: .actions, start: 2.3, length: 0.4),
    ])

    var duration: TimeInterval { cues.map { $0.start + $0.length }.max() ?? 0 }

    /// How far a beat has come in at `time`, from 0 (not started) to 1 (settled), eased.
    func progress(_ beat: Beat, at time: TimeInterval) -> Double {
        guard let cue = cues.first(where: { $0.beat == beat }) else { return 1 }
        let raw = min(max((time - cue.start) / cue.length, 0), 1)
        return raw * raw * (3 - 2 * raw)
    }

    /// A beat on a critically damped spring, from 0 to 1 and never past it: quick at first, settling over its length
    /// (98% of the way at its end).
    func spring(_ beat: Beat, at time: TimeInterval) -> Double {
        guard let cue = cues.first(where: { $0.beat == beat }) else { return 1 }
        let elapsed = max(time - cue.start, 0)
        let omega = 6 / cue.length
        return 1 - (1 + omega * elapsed) * exp(-omega * elapsed)
    }

    /// The beats that have started by `time`, in the order they play.
    func started(at time: TimeInterval) -> [Beat] {
        cues.filter { $0.start <= time }.map(\.beat)
    }
}
