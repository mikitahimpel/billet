import Testing

@testable import FeatureShop

@Suite struct GiftWordsTests {
  @Test func oneCoinIsSingular() {
    #expect(GiftWords.coins(1) == "+1 coin")
    #expect(GiftWords.coins(5) == "+5 coins")
  }
}
