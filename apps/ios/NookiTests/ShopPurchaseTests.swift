import Foundation
import Testing
@testable import Billet

private let t0 = Date(timeIntervalSinceReferenceDate: 815_000_000)

@Suite struct ShopPurchaseTests {
    @Test func buyingTakesTheCostAndAddsOnlyNewPieces() {
        var wallet = Wallet(coins: 500, owned: ["lamp"], wishlist: ["armchair"])
        let purchase = wallet.buy(["lamp", "armchair", "print"], cost: 300, title: "Rainy Evening", at: t0)!
        #expect(wallet.coins == 200)
        #expect(wallet.owned == ["lamp", "armchair", "print"])
        #expect(wallet.wishlist.isEmpty)
        #expect(purchase.added.sorted() == ["armchair", "print"])
    }

    @Test func aBuyThatCannotBePaidOrAddsNothingChangesNothing() {
        var wallet = Wallet(coins: 100, owned: ["lamp"])
        #expect(wallet.buy(["armchair"], cost: 320, title: "Cloud Armchair", at: t0) == nil)
        #expect(wallet.buy(["lamp"], cost: 50, title: "Mushroom Lamp", at: t0) == nil)
        #expect(wallet.coins == 100)
        #expect(wallet.owned == ["lamp"])
    }

    @Test func undoGivesTheCoinsBackAndKeepsWhatWasOwnedBefore() {
        var wallet = Wallet(coins: 500, owned: ["lamp"])
        let purchase = wallet.buy(["lamp", "armchair"], cost: 230, title: "Set", at: t0)!
        wallet.undo(purchase)
        #expect(wallet.coins == 500)
        #expect(wallet.owned == ["lamp"])
    }

    @Test func aGiftIsMarkedAndItsUndoUnmarksIt() {
        var wallet = Wallet(coins: 200, owned: [])
        let purchase = wallet.buy(["yarn"], cost: 60, title: "Yarn Ball", giftTo: true, at: t0)!
        #expect(wallet.gifted == ["yarn"])
        wallet.undo(purchase)
        #expect(wallet.gifted.isEmpty)
    }

    @Test func undoLastsFiveSeconds() {
        var wallet = Wallet(coins: 200, owned: [])
        let purchase = wallet.buy(["yarn"], cost: 60, title: "Yarn Ball", at: t0)!
        #expect(purchase.canUndo(at: t0.addingTimeInterval(4.9)))
        #expect(!purchase.canUndo(at: t0.addingTimeInterval(5)))
    }

    @Test func openingTheShopAtAnInkSwitchesTabAndLeavesTheFocus() {
        let state = HomeState(stores: .live())
        state.openShop(.ink("ink-rose"))
        #expect(state.tab == .shop)
        #expect(state.shopFocus == .ink("ink-rose"))
    }
}
