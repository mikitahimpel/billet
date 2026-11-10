import Design
import Testing
@testable import Billet

/// Where the "is yours" card floats: clear of the tab bar on Home, clear of the home indicator elsewhere.
@MainActor
@Suite struct PurchaseMomentTests {
    @Test func overTheTabBarItKeepsAGapAboveItsTopEdge() {
        // A 874 pt screen whose tab bar starts at 790.
        let lift = PurchaseMoment.lift(bottom: 874, floor: 790, safeBottom: 34)
        #expect(874 - lift == 790 - Space.m)
    }

    @Test func withoutABarItSitsOverTheHomeIndicator() {
        #expect(PurchaseMoment.lift(bottom: 874, floor: nil, safeBottom: 34) == 34 + Space.l)
    }

    @Test func aBarBelowTheContainerIsIgnored() {
        #expect(PurchaseMoment.lift(bottom: 700, floor: 790, safeBottom: 0) == Space.l)
    }
}
