import FeatureMischief
import Foundation
import MischiefInterface
import Testing
@testable import Billet

@Suite struct HuntStripTests {
    private let hide = MischiefHide(id: "h", by: "leo", spot: .basket, line: nil, at: .now, found: nil)

    private func hunt(_ looks: [(MischiefSpot, Warmth)]) -> MischiefHuntMachine.Hunt {
        var state = MischiefHuntMachine.State.hunting(.init(hide: hide, startedAt: .now))
        for (spot, warmth) in looks { state = MischiefHuntMachine.transition(state, .look(spot, warmth: warmth, at: .now)).0 }
        guard case .hunting(let hunt) = state else { fatalError("not hunting") }
        return hunt
    }

    @Test func beforeALookSheNamesTheHider() {
        #expect(HuntStrip.words(hunt([]), cat: "Mochi", partner: "Leo") == "Where did Leo hide it? Mochi knows.")
    }

    @Test(arguments: [
        (Warmth.cold, "Mochi yawns. Not there."), (.cool, "Mochi's ear flicks."),
        (.warm, "Mochi's ears go up. Close."), (.hot, "Mochi sniffs. Very close."),
    ])
    func eachLookGetsItsLine(warmth: Warmth, line: String) {
        #expect(HuntStrip.words(hunt([(.sill, warmth)]), cat: "Mochi", partner: "Leo") == line)
    }

    @Test func afterThreeMissesSheShowsTheWay() {
        let looks: [(MischiefSpot, Warmth)] = [(.sill, .cold), (.tree, .cold), (.crate, .cool)]
        #expect(HuntStrip.words(hunt(looks), cat: "Mochi", partner: "Leo") == "Mochi is showing you.")
    }
}
