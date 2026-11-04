import Payments
import Pet
import Synchronization
import Testing

@testable import FeatureHome

/// A store that answers what the test says, and a ledger the test sets.
private final class ScriptedPayments: Payments {
  let result = Mutex<Result<PurchaseResult, PaymentsError>>(.success(.cancelled))
  let ledger = Mutex(StampLedger.empty)
  private let continuation = Mutex<AsyncStream<PaymentsUpdate>.Continuation?>(nil)

  func products() async throws(PaymentsError) -> [StampPack] {
    [StampPack(id: "p100", stamps: 100, displayName: "100", description: "", displayPrice: "$1")]
  }

  func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult {
    try result.withLock { $0 }.get()
  }

  func restore() async throws(PaymentsError) -> StampLedger { ledger.withLock { $0 } }

  func updates() -> AsyncStream<PaymentsUpdate> {
    let (stream, continuation) = AsyncStream<PaymentsUpdate>.makeStream()
    self.continuation.withLock { $0 = continuation }
    return stream
  }

  func send(_ update: PaymentsUpdate) { _ = continuation.withLock { $0?.yield(update) } }
}

@MainActor
@Suite struct StampShopTests {
  private static func credit(_ id: String, _ stamps: Int) -> StampCredit {
    StampCredit(
      entryID: "purchase:\(id)", transactionID: id, productID: "p100", stamps: stamps,
      serverBalance: stamps, duplicate: false)
  }

  private func make() -> (StampShop, ScriptedPayments, ShopStore) {
    let payments = ScriptedPayments()
    let shop = ShopStore(storage: .memory(), grant: 0)
    let stampShop = StampShop(payments: payments)
    return (stampShop, payments, shop)
  }

  @Test func aPurchaseAddsTheStampsToTheWallet() async throws {
    let (stampShop, payments, shop) = make()
    stampShop.attach(shop)
    await stampShop.load()
    payments.result.withLock { $0 = .success(.purchased(Self.credit("t1", 100))) }
    await stampShop.buy(try #require(stampShop.packs.first))
    #expect(shop.stamps == 100)
    #expect(stampShop.state == .bought(Self.credit("t1", 100)))
  }

  @Test func cancelAndFailureLeaveTheWalletAlone() async throws {
    let (stampShop, payments, shop) = make()
    stampShop.attach(shop)
    await stampShop.load()
    let pack = try #require(stampShop.packs.first)
    await stampShop.buy(pack)
    #expect(stampShop.state == .idle)
    payments.result.withLock { $0 = .failure(.unavailable) }
    await stampShop.buy(pack)
    guard case .failed = stampShop.state else {
      Issue.record("expected a failure, got \(stampShop.state)")
      return
    }
    #expect(shop.stamps == 0)
  }

  @Test func theServerLedgerIsMergedAndRefundsAreRevoked() async {
    let (stampShop, payments, shop) = make()
    payments.ledger.withLock {
      $0 = StampLedger(
        balance: 0,
        entries: [
          .init(id: "purchase:t1", kind: .purchase, amount: 550, productID: "p550"),
          .init(id: "refund:t1", kind: .refund, amount: -550, productID: "p550"),
          .init(id: "purchase:t2", kind: .purchase, amount: 100, productID: "p100"),
        ])
    }
    stampShop.attach(shop)
    await stampShop.sync()
    #expect(shop.stamps == 100)
    #expect(shop.state.wallet.hasEntry("revoked:t1"))
    await stampShop.sync()
    #expect(shop.stamps == 100)
  }

  @Test func revokedIDsKeepTheTransaction() {
    #expect(StampShop.revokedID(for: "refund:t1") == "revoked:t1")
    #expect(StampShop.revokedID(for: "refund:t1:2") == "revoked:t1:2")
  }
}
