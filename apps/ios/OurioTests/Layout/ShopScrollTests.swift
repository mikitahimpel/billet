import FeatureShop
import SwiftUI
import Testing
@testable import Billet

/// The Shop is one plain vertical scroll: only its deals row scrolls sideways (its category row is the header's).
@MainActor @Suite(.serialized) struct ShopScrollTests {
    @Test func theShopScrollsOnlyUpAndDown() {
        UserDefaults.standard.set(true, forKey: "uitestStill")
        let state = HomeState(stores: .live())
        state.tab = .shop
        let layout = HostedLayout(ShopView(state: state), phone: .se)
        layout.settle(1)
        let page = layout.scrollViews.max { $0.bounds.height < $1.bounds.height }
        #expect(page != nil)
        #expect((page?.contentSize.width ?? 0) <= (page?.bounds.width ?? 0) + 1, "the page does not scroll sideways")
        for step in 0..<4 {
            #expect(layout.scrollViews.count <= 2, "only the page and the deals row scroll (step \(step))")
            if let page {
                page.setContentOffset(CGPoint(x: 0, y: min(page.contentSize.height - page.bounds.height, CGFloat(step + 1) * 500)), animated: false)
            }
            layout.settle(0.4)
        }
        #expect(layout.scrollViews.count <= 2, "only the page and the deals row scroll after scrolling down")
        let sideways = layout.scrollViews.filter { $0 !== page && $0.contentSize.height > $0.bounds.height + 1 }
        #expect(sideways.isEmpty, "the rows scroll only sideways")
    }
}
