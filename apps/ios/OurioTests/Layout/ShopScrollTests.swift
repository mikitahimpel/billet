import Design
import FeatureShop
import SwiftUI
import Testing
@testable import Billet

/// The Shop is one plain vertical scroll: only its deals row scrolls sideways (its category row is the header's).
@MainActor @Suite(.serialized) struct ShopScrollTests {
    @Test func theShopScrollsOnlyUpAndDown() {
        UserDefaults.standard.set(true, forKey: "uitestStill")
        let state = HomeState(stores: .live(events: .none))
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

    /// Today's section headers start at one left edge, the deals' (whose row scrolls edge to edge) with the rest.
    @Test func theTodaySectionHeadersShareOneLeftEdge() throws {
        UserDefaults.standard.set(true, forKey: "uitestStill")
        let state = HomeState(stores: .live(events: .none))
        state.tab = .shop
        state.shopCategory = .today
        let layout = HostedLayout(ShopView(state: state), phone: .se)
        layout.settle(1)
        let page = try #require(layout.scrollViews.max { $0.bounds.height < $1.bounds.height })
        let deals = try #require(layout.element(label: "Daily deals"), "no deals header").frame
        var bundles = layout.element(label: "Bundles")
        var step = 0
        while bundles == nil, step < 8 {
            step += 1
            let y = min(page.contentSize.height - page.bounds.height, CGFloat(step) * 400)
            page.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            layout.settle(0.4)
            bundles = layout.element(label: "Bundles")
        }
        let bundlesFrame = try #require(bundles, "no bundles header").frame
        #expect(abs(deals.minX - bundlesFrame.minX) < 1, "deals at \(deals.minX), bundles at \(bundlesFrame.minX)")
        #expect(deals.minX >= Space.l + Space.s, "the deals header is in from the edge")
    }
}
