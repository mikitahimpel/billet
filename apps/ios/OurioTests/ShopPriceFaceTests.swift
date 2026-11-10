import Testing
@testable import Billet

@Suite struct ShopPriceFaceTests {
    @Test func enoughCoinsBuysAtThePrice() {
        let face = ShopPriceFace(price: 90, was: 120, coins: 90, owned: false)
        #expect(face == .buy(price: 90, was: 120))
        #expect(face.tap == .buy)
    }

    @Test func aWasThatIsNotHigherIsDropped() {
        #expect(ShopPriceFace(price: 90, was: 90, coins: 500, owned: false) == .buy(price: 90, was: nil))
        #expect(ShopPriceFace(price: 90, was: 40, coins: 500, owned: false) == .buy(price: 90, was: nil))
    }

    @Test func shortOfCoinsShowsTheShortfallAndOpensCoinsAtIt() {
        let face = ShopPriceFace(price: 90, coins: 50, owned: false)
        #expect(face == .short(missing: 40))
        #expect(face.tap == .askForCoins(missing: 40))
        #expect(ShopPriceFace(price: 90, coins: 89, owned: false) == .short(missing: 1))
        #expect(ShopPriceFace(price: 90, coins: 0, owned: false) == .short(missing: 90))
    }

    @Test func ownedIgnoresTheBalanceAndRejectsTheTap() {
        #expect(ShopPriceFace(price: 90, coins: 0, owned: true) == .owned)
        #expect(ShopPriceFace(price: 90, coins: 1000, owned: true).tap == .none)
    }
}
