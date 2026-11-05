import Foundation
import Testing
import Wire
@testable import Billet

private let t0 = Date(timeIntervalSinceReferenceDate: 815_000_000)

@Suite struct ShopPurchaseTests {
    private func purchase(kind: Purchase.Kind = .item) -> Purchase {
        Purchase(
            offer: .item(RoomItemId("yarn")), itemIDs: ["yarn"], added: ["yarn"], cost: 60, date: t0, title: "Yarn Ball",
            kind: kind)
    }

    @Test func undoLastsFiveSeconds() {
        let purchase = purchase()
        #expect(purchase.canUndo(at: t0.addingTimeInterval(4.9)))
        #expect(!purchase.canUndo(at: t0.addingTimeInterval(5)))
    }

    @Test func aTreatHasNoUndo() {
        #expect(!purchase(kind: .treat).canUndo(at: t0))
    }

    @Test func eachTapIsItsOwnOrderId() {
        let first = purchase(), second = purchase()
        #expect(first.key != second.key)
        #expect(first.key == IdempotencyKey(first.id.uuidString))
    }

    @Test func openingTheShopAtAnInkSwitchesTabAndLeavesTheFocus() {
        let state = HomeState(stores: .live())
        state.openShop(.ink("ink-rose"))
        #expect(state.tab == .shop)
        #expect(state.shopFocus == .ink("ink-rose"))
    }

    @Test func theCoinsOpenTheShopAtTheCoinsBlock() {
        let state = HomeState(stores: .live())
        state.openShop(.coins)
        #expect(state.tab == .shop)
        #expect(state.shopFocus == .coins)
    }
}
