import Foundation
import Payments
import PaymentsMock
import Synchronization
import Testing

/// A dev server in memory: credits each transaction once and keeps the ledger.
private final class FakeServer: Sendable {
  private let entries = Mutex<[StampLedger.Entry]>([])
  let calls = Mutex<[String]>([])

  var server: PaymentsServer {
    PaymentsServer(
      verify: { (_) async throws(PaymentsError) in throw .rejected },
      mock: { (product, transaction, kind) async throws(PaymentsError) in
        self.mock(product, transaction, kind)
      },
      ledger: { () async throws(PaymentsError) in self.ledger })
  }

  var ledger: StampLedger {
    entries.withLock { StampLedger(balance: max(0, $0.reduce(0) { $0 + $1.amount }), entries: $0) }
  }

  private func mock(_ product: String, _ transaction: String, _ kind: PaymentsServer.MockKind)
    -> PaymentsServer.Answer
  {
    calls.withLock { $0.append("\(kind.rawValue) \(product)") }
    let stamps = StampPackCatalog.standard.definition(product)?.stamps ?? 0
    let id = "\(kind.rawValue):\(transaction)"
    let duplicate = entries.withLock { entries in
      guard !entries.contains(where: { $0.id == id }) else { return true }
      let kindValue: StampLedger.Kind = kind == .purchase ? .purchase : .refund
      entries.append(
        .init(
          id: id, kind: kindValue, amount: kind == .purchase ? stamps : -stamps,
          productID: product))
      return false
    }
    return .init(
      transactionID: transaction, productID: product, stamps: stamps, balance: ledger.balance,
      duplicate: duplicate)
  }
}

@Suite struct MockPaymentsTests {
  private func payments(
    _ outcome: MockSwitches.Outcome, server: FakeServer, ids: [String] = ["t1", "t2", "t3"]
  ) -> MockPayments {
    let queue = Mutex(ids)
    return MockPayments(
      server: server.server, switches: .fixed(outcome),
      makeID: { queue.withLock { $0.removeFirst() } })
  }

  @Test func theBundledListHasThreePacksInOrder() {
    #expect(
      StampPackCatalog.standard.productIDs == [
        "com.mikitahimpel.billet.coins.100", "com.mikitahimpel.billet.coins.550",
        "com.mikitahimpel.billet.coins.1200",
      ])
    #expect(StampPackCatalog.standard.packs.map(\.stamps) == [100, 550, 1200])
  }

  @Test func aPurchaseIsCreditedByTheServer() async throws {
    let server = FakeServer()
    let mock = payments(.succeed, server: server)
    let pack = try await mock.products()[1]
    let result = try await mock.purchase(pack)
    guard case .purchased(let credit) = result else {
      Issue.record("expected a purchase, got \(result)")
      return
    }
    #expect(credit.entryID == "purchase:t1")
    #expect(credit.stamps == 550)
    #expect(credit.serverBalance == 550)
    #expect(server.calls.withLock { $0 } == ["purchase com.mikitahimpel.billet.coins.550"])
  }

  @Test func cancelAndFailNeverReachTheServer() async throws {
    let server = FakeServer()
    let pack = try await payments(.succeed, server: server).products()[0]
    #expect(try await payments(.cancel, server: server).purchase(pack) == .cancelled)
    await #expect(throws: PaymentsError.self) {
      try await payments(.fail, server: server).purchase(pack)
    }
    #expect(server.calls.withLock { $0 }.isEmpty)
  }

  @Test func askToBuyIsCreditedWhenApproved() async throws {
    let server = FakeServer()
    let mock = payments(.pending, server: server)
    let pack = try await mock.products()[0]
    let updates = mock.updates()
    #expect(try await mock.purchase(pack) == .pending)
    #expect(mock.pendingCount == 1)
    try await mock.approvePending()
    var iterator = updates.makeAsyncIterator()
    guard case .credited(let credit) = await iterator.next() else {
      Issue.record("expected a credit")
      return
    }
    #expect(credit.stamps == 100)
    #expect(mock.pendingCount == 0)
  }

  @Test func aDeclinedAskToBuyChargesNothing() async throws {
    let server = FakeServer()
    let mock = payments(.pending, server: server)
    _ = try await mock.purchase(try await mock.products()[0])
    mock.declinePending()
    #expect(mock.pendingCount == 0)
    #expect(server.ledger.balance == 0)
  }

  @Test func aRefundTakesTheLastPurchaseBack() async throws {
    let server = FakeServer()
    let mock = payments(.succeed, server: server)
    let updates = mock.updates()
    _ = try await mock.purchase(try await mock.products()[2])
    #expect(try await mock.refundLast())
    var iterator = updates.makeAsyncIterator()
    guard case .ledgerChanged(let ledger) = await iterator.next() else {
      Issue.record("expected a ledger change")
      return
    }
    #expect(ledger.balance == 0)
    #expect(ledger.entries.map(\.id) == ["purchase:t1", "refund:t1"])
    #expect(try await mock.refundLast() == false)
  }

  @Test func anUnknownPackIsRefused() async {
    let mock = payments(.succeed, server: FakeServer())
    let pack = StampPack(
      id: "com.example.nope", stamps: 1, displayName: "", description: "", displayPrice: "")
    await #expect(throws: PaymentsError.unknownProduct("com.example.nope")) {
      try await mock.purchase(pack)
    }
  }
}
