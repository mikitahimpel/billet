import Payments
import PaymentsStoreKit
import StoreKitTest
import Synchronization
import XCTest

/// Buys every stamp pack from Billet.storekit on the Simulator with StoreKitPayments, against a
/// server that records what it is sent. Proves the products load, a purchase reaches the server as
/// a signed transaction, and the transaction is finished only after the server answered.
final class StoreKitPurchaseTests: XCTestCase {
  private var session: SKTestSession!

  override func setUp() async throws {
    session = try SKTestSession(configurationFileNamed: "Billet")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
  }

  private final class Recorder: Sendable {
    let sent = Mutex<[String]>([])
    let failNext = Mutex(false)

    var server: PaymentsServer {
      PaymentsServer(
        verify: { (jws) async throws(PaymentsError) in
          if self.failNext.withLock({ let fail = $0; $0 = false; return fail }) {
            throw .unavailable
          }
          self.sent.withLock { $0.append(jws) }
          let product = Self.claim("productId", in: jws) ?? ""
          let stamps = StampPackCatalog.standard.definition(product)?.stamps ?? 0
          return .init(
            transactionID: Self.claim("originalTransactionId", in: jws) ?? "", productID: product,
            stamps: stamps, balance: stamps, duplicate: false)
        },
        mock: { (_, _, _) async throws(PaymentsError) in throw .rejected },
        ledger: { () async throws(PaymentsError) in .empty })
    }

    /// One claim of the JWS payload, read without checking the signature (the server checks it).
    static func claim(_ name: String, in jws: String) -> String? {
      let parts = jws.split(separator: ".")
      guard parts.count == 3 else { return nil }
      var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
      base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
      guard let data = Data(base64Encoded: base64),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return nil }
      return object[name].map { "\($0)" }
    }
  }

  func testTheStoreSellsEveryPackInTheCatalogue() async throws {
    let payments = StoreKitPayments(server: Recorder().server)
    let packs = try await payments.products()
    XCTAssertEqual(packs.map(\.id), StampPackCatalog.standard.productIDs)
    XCTAssertEqual(packs.map(\.stamps), [100, 550, 1200])
    XCTAssertEqual(packs.map(\.displayPrice).count, 3)
  }

  func testAPurchaseSendsTheSignedTransactionAndIsCredited() async throws {
    let recorder = Recorder()
    let payments = StoreKitPayments(server: recorder.server)
    for pack in try await payments.products() {
      let result = try await payments.purchase(pack)
      guard case .purchased(let credit) = result else {
        return XCTFail("\(pack.id): expected a purchase, got \(result)")
      }
      XCTAssertEqual(credit.productID, pack.id)
      XCTAssertEqual(credit.stamps, pack.stamps)
    }
    let sent = recorder.sent.withLock { $0 }
    XCTAssertEqual(sent.count, 3)
    XCTAssertEqual(
      sent.compactMap { Recorder.claim("bundleId", in: $0) },
      Array(repeating: "com.mikitahimpel.billet", count: 3))
    XCTAssertEqual(sent.compactMap { Recorder.claim("environment", in: $0) }.first, "Xcode")
    // Finished after the server answered: nothing is left for restore to send again.
    var unfinished = 0
    for await _ in Transaction.unfinished { unfinished += 1 }
    XCTAssertEqual(unfinished, 0)
  }

  func testATransactionTheServerMissedStaysUnfinishedAndRestoreSendsItAgain() async throws {
    let recorder = Recorder()
    recorder.failNext.withLock { $0 = true }
    let payments = StoreKitPayments(server: recorder.server)
    let pack = try await payments.products()[0]
    do {
      _ = try await payments.purchase(pack)
      XCTFail("the server was down, so the purchase should have failed")
    } catch {}
    var unfinished = 0
    for await _ in Transaction.unfinished { unfinished += 1 }
    XCTAssertEqual(unfinished, 1)
    _ = try await payments.restore()
    XCTAssertEqual(recorder.sent.withLock { $0.count }, 1)
    unfinished = 0
    for await _ in Transaction.unfinished { unfinished += 1 }
    XCTAssertEqual(unfinished, 0)
  }

  func testAFailedStorePurchaseIsAnError() async throws {
    session.failTransactionsEnabled = true
    session.failureError = .unknown
    let payments = StoreKitPayments(server: Recorder().server)
    let pack = try await payments.products()[0]
    do {
      _ = try await payments.purchase(pack)
      XCTFail("expected a failure")
    } catch {}
  }
}
