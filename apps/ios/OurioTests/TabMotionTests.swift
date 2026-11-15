import CoreGraphics
import Testing
@testable import Billet

/// The selection pill sits at a tab's slot and a touch picks the tab under it, both in the bar's order.
struct TabMotionTests {
    @Test func theBarRunsWorldMomentsShopUs() {
        #expect(HomeTab.allCases == [.world, .moments, .shop, .us])
        #expect(HomeTab.allCases.map(\.order) == [0, 1, 2, 3])
    }

    @Test(arguments: [
        (CGFloat(0), HomeTab.world),
        (99, .world),
        (100, .moments),
        (250, .shop),
        (399, .us),
    ])
    func aTouchPicksTheTabUnderIt(x: CGFloat, tab: HomeTab) {
        #expect(HomeTab.at(x, across: 400) == tab)
    }

    @Test func pastTheEndsIsTheFirstOrLastTab() {
        #expect(HomeTab.at(-30, across: 400) == .world)
        #expect(HomeTab.at(430, across: 400) == .us)
    }

    @Test(arguments: HomeTab.allCases)
    func theMiddleOfATabsSlotIsThatTab(tab: HomeTab) {
        let slot: CGFloat = 100
        #expect(HomeTab.at(slot * (CGFloat(tab.order) + 0.5), across: 400) == tab)
    }

    @Test func noWidthNoTab() {
        #expect(HomeTab.at(10, across: 0) == nil)
    }
}

/// The page switches when the finger lands on its tab, not when the finger lifts.
struct TabScrubTests {
    @Test func landingOnAnotherTabShowsItAtOnce() {
        let move = TabScrub().finger(on: .shop, shown: .world)
        #expect(move == TabScrub.Move(scrub: TabScrub(hovered: .shop), shows: .shop))
    }

    @Test func landingOnTheShownTabOnlyHoversIt() {
        let move = TabScrub().finger(on: .world, shown: .world)
        #expect(move == TabScrub.Move(scrub: TabScrub(hovered: .world), shows: nil))
    }

    @Test func movingWithinTheSlotIsNotAMove() {
        #expect(TabScrub(hovered: .shop).finger(on: .shop, shown: .shop) == nil)
    }

    @Test func slidingOntoTheNextTabShowsIt() {
        let move = TabScrub(hovered: .moments).finger(on: .shop, shown: .moments)
        #expect(move == TabScrub.Move(scrub: TabScrub(hovered: .shop), shows: .shop))
    }

    @Test func slidingBackOntoTheShownTabShowsNothingNew() {
        let move = TabScrub(hovered: .shop).finger(on: .us, shown: .us)
        #expect(move == TabScrub.Move(scrub: TabScrub(hovered: .us), shows: nil))
    }

    @Test func liftingClearsTheHoverAndSwitchesNothing() {
        #expect(TabScrub(hovered: .us).lifted() == TabScrub())
    }
}
