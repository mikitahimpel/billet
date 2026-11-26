import Pet
import Testing
@testable import Billet

@MainActor
struct CatLivelyTests {
    private func cat(seed: UInt64? = 3) -> CatBehavior {
        let cat = CatBehavior(tailJoints: 3)
        cat.directed = true
        cat.noticing = seed.map(CatNoticing.init)
        return cat
    }

    /// Steps `cat` for `seconds` at 60 frames a second and returns each frame's values.
    private func run(_ cat: CatBehavior, _ seconds: Float) -> [CatBehavior.Values] {
        (0..<Int(seconds * 60)).map { _ in
            cat.update(1 / 60, eyes: [0, 0.1, -0.05])
            return cat.state
        }
    }

    @Test func anEarTurnsToASoundBeforeTheHeadDoes() {
        let cat = cat()
        _ = run(cat, 0.5)
        let before = cat.state
        cat.notice(.partner, .heard, bearing: -1.3, salience: 0.9, hold: 2)
        let frames = run(cat, 1.5)
        let ear = frames.firstIndex { $0.earTurnLeft - before.earTurnLeft > 0.15 }
        let head = frames.firstIndex { $0.yaw - before.yaw < -0.15 }
        #expect(ear != nil && head != nil)
        if let ear, let head { #expect(ear < head) }
        #expect((frames.last?.yaw ?? 0) < -0.4)
    }

    @Test func aStartTurnsTheHeadFasterThanALazyLook() {
        func peak(_ salience: Float) -> Float {
            let cat = cat()
            _ = run(cat, 0.5)
            cat.notice(.touch, .own, bearing: 0.5, salience: salience, hold: 2)
            let frames = run(cat, 1)
            return zip(frames, frames.dropFirst()).map { abs($1.yaw - $0.yaw) * 60 }.max() ?? 0
        }
        #expect(peak(1) > 1.3 * peak(0.45))
    }

    @Test func staringSheHoldsHerTailButForItsTip() {
        let cat = cat()
        _ = run(cat, 3)
        cat.notice(.touch, .own, bearing: 0.3, salience: 0.9, hold: 6)
        let frames = run(cat, 4).dropFirst(90)
        let base = frames.map(\.tailSway[0])
        #expect((base.max() ?? 0) - (base.min() ?? 0) < 0.03)
    }

    @Test func theSameSeedPlaysTheSameLooks() {
        func looks(_ seed: UInt64) -> [Float] {
            let cat = cat(seed: seed)
            cat.ambient = [CatStimulus(.place("sill"), .seen, bearing: -0.5, elevation: 0.2, salience: 0.5, hold: 3)]
            return run(cat, 20).map(\.yaw)
        }
        #expect(looks(5) == looks(5))
        #expect(looks(5) != looks(6))
    }

    @Test func withoutAnAttentionNoticingDoesNothing() {
        let cat = cat(seed: nil)
        cat.notice(.partner, .heard, bearing: -1.3, salience: 0.9, hold: 2)
        #expect(cat.survey() == 0)
        #expect(cat.noticing == nil)
    }

    @Test func onlyHerUsualPaceLingers() {
        #expect(CatPace.usual.regard.lowerBound > 0.3)
        #expect(CatPace.usual.surveys)
        #expect(CatPace.eager.regard == 0...0)
        #expect(!CatPace.eager.surveys)
    }
}
