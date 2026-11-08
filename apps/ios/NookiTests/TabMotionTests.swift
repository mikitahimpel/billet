import Design
import Testing
@testable import Billet

/// The side a tab's page comes in from follows the tab bar's order.
struct TabMotionTests {
    @Test func theBarRunsWorldMomentsShopUs() {
        #expect(HomeTab.allCases == [.world, .moments, .shop, .us])
        #expect(HomeTab.allCases.map(\.order) == [0, 1, 2, 3])
    }

    @Test(arguments: [
        (HomeTab.world, HomeTab.shop, Motion.Direction.forward),
        (.world, .us, .forward),
        (.moments, .shop, .forward),
        (.shop, .us, .forward),
        (.us, .shop, .backward),
        (.shop, .world, .backward),
        (.us, .moments, .backward),
        (.moments, .world, .backward),
    ])
    func aSwitchMovesTowardsTheNewTab(from old: HomeTab, to new: HomeTab, direction: Motion.Direction) {
        #expect(HomeTab.direction(from: old, to: new) == direction)
    }

    @Test(arguments: HomeTab.allCases)
    func noSwitchStaysStill(tab: HomeTab) {
        #expect(HomeTab.direction(from: tab, to: tab) == .still)
    }

    @Test func goingThereAndBackMirrors() {
        for old in HomeTab.allCases {
            for new in HomeTab.allCases where new != old {
                let there = HomeTab.direction(from: old, to: new)
                let back = HomeTab.direction(from: new, to: old)
                #expect(there != back)
                #expect(Motion.entryOffset(there, reduceMotion: false) == -Motion.entryOffset(back, reduceMotion: false))
            }
        }
    }

    @Test func reduceMotionSwitchesTabsWithAFadeAlone() {
        for old in HomeTab.allCases {
            for new in HomeTab.allCases {
                #expect(Motion.entryOffset(HomeTab.direction(from: old, to: new), reduceMotion: true) == 0)
            }
        }
    }
}
