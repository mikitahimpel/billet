import Testing

@testable import Pet

/// Stamps bought for money and taken back after an App Store refund.
@MainActor
@Suite struct StampPurchaseTests {
  private func store(grant: Int = 0) -> ShopStore {
    ShopStore(storage: .memory(), grant: grant)
  }

  @Test func aPurchaseIsCreditedOnce() {
    let shop = store()
    #expect(shop.creditPurchase(550, id: "purchase:1") == .applied)
    #expect(shop.creditPurchase(550, id: "purchase:1") == .duplicate)
    #expect(shop.stamps == 550)
  }

  @Test func aRevokeTakesTheStampsBackOnce() {
    let shop = store()
    shop.creditPurchase(100, id: "purchase:1")
    #expect(shop.revokePurchase(100, id: "revoked:1") == 100)
    #expect(shop.revokePurchase(100, id: "revoked:1") == nil)
    #expect(shop.stamps == 0)
  }

  @Test func aRevokeNeverGoesBelowZero() {
    var wallet = StampWallet()
    _ = wallet.credit(100, as: .purchase, id: "purchase:1")
    _ = try? wallet.debit(70, id: "spend:a")
    #expect(wallet.revoke(100, id: "revoked:1") == 30)
    #expect(wallet.balance == 0)
    #expect(wallet.entries.last?.source == .revoked)
  }

  @Test func aRevokeIsNotTheShopsOwnUndoRefund() {
    var wallet = StampWallet()
    _ = wallet.credit(100, as: .purchase, id: "purchase:1")
    _ = wallet.revoke(100, id: "revoked:1")
    // The undo's id space (refund:) stays free.
    #expect(wallet.credit(40, as: .refund, id: "refund:1") == .applied)
  }
}
