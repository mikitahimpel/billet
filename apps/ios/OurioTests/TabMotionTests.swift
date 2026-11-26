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

/// The finger on the bar: every state against every event, the rejected pair included.
struct TabBarMachineTests {
    typealias Machine = TabBarMachine

    @Test(arguments: HomeTab.allCases)
    func landingHoversTheTabUnderTheFinger(tab: HomeTab) {
        #expect(Machine.transition(.idle, .landed(tab)) == (.touched(tab), []))
    }

    @Test(arguments: HomeTab.allCases, HomeTab.allCases)
    func slidingOntoASlotHoversIt(from: HomeTab, to: HomeTab) {
        #expect(Machine.transition(.touched(from), .landed(to)) == (.touched(to), []))
    }

    @Test(arguments: HomeTab.allCases)
    func liftingEndsTheHover(tab: HomeTab) {
        #expect(Machine.transition(.touched(tab), .lifted) == (.idle, []))
    }

    @Test func aSecondLiftChangesNothing() {
        #expect(Machine.transition(.idle, .lifted) == (.idle, []))
    }

    @Test func onlyATouchedBarHovers() {
        #expect(Machine.State.idle.hovered == nil)
        #expect(HomeTab.allCases.compactMap { Machine.State.touched($0).hovered } == HomeTab.allCases)
    }
}
