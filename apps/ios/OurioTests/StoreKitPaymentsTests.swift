#if PAYMENTS_STOREKIT
import Foundation
import Payments
import PaymentsStoreKit
import StoreKitTest
import Synchronization
import Testing

/// The StoreKit store against `Ourio.storekit`, in a `storekit` build on a Simulator before iOS 26.3 (docs/payments.md):
/// every pack is bought, each transaction reaches the server once, and a refunded one is never sent again.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct StoreKitPaymentsTests {
    private static let configuration = Repo.root.appending(path: "apps/ios/Ourio.storekit")

    @Test func everyPackIsBoughtAndARefundIsFollowed() async throws {
        let session = try SKTestSession(contentsOf: Self.configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let server = RecordingServer()
        let payments = StoreKitPayments(server: server.server)
        payments.start()

        let packs = try await payments.products()
        #expect(packs.map(\.stamps) == [100, 550, 1200])
        #expect(packs.map(\.displayPrice) == ["$0.99", "$4.99", "$9.99"])
        for pack in packs {
            guard case .purchased(let credit) = try await payments.purchase(pack) else {
                Issue.record("\(pack.id) was not credited")
                continue
            }
            #expect(credit.stamps == pack.stamps)
        }
        #expect(server.verified.withLock { $0 } == 3)

        // Xcode's StoreKit testing doesn't announce a refund on `Transaction.updates`; the server learns of it from
        // Apple. What the device must never do is send a refunded transaction for credit again.
        let bought = try #require(session.allTransactions().first { $0.productIdentifier == packs[0].id })
        try session.refundTransaction(identifier: bought.identifier)
        await payments.settleUnfinished()
        #expect(server.verified.withLock { $0 } == 3)
    }

    @Test func aPaidPackTheServerMissedStaysUnfinishedUntilItIsSent() async throws {
        let session = try SKTestSession(contentsOf: Self.configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let server = RecordingServer(down: true)
        let payments = StoreKitPayments(server: server.server)
        let pack = try #require(try await payments.products().first)

        #expect(try await payments.purchase(pack) == .awaitingCredit)
        server.down.withLock { $0 = false }
        let updates = payments.updates()
        await payments.settleUnfinished()
        var credited: StampCredit?
        for await update in updates {
            if case .credited(let credit) = update {
                credited = credit
                break
            }
        }
        #expect(credited?.stamps == pack.stamps)
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        #expect(unfinished == 0)
    }
}

/// The server half: answers each signed transaction as credited, or as unreachable while `down`.
nonisolated private final class RecordingServer: Sendable {
    let verified = Mutex(0)
    let down: Mutex<Bool>

    init(down: Bool = false) { self.down = Mutex(down) }

    var server: PaymentsServer {
        PaymentsServer(
            verify: { (jws) async throws(PaymentsError) in try self.verify(jws) },
            mock: { (_, _, _) async throws(PaymentsError) in throw .unavailable },
            ledger: { () async throws(PaymentsError) in .empty })
    }

    private func verify(_ jws: String) throws(PaymentsError) -> PaymentsServer.Answer {
        if down.withLock({ $0 }) { throw .unavailable }
        let payload = jws.split(separator: ".").dropFirst().first.map(String.init) ?? ""
        let data = Data(base64Encoded: Self.padded(payload)) ?? Data()
        let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let product = claims["productId"] as? String ?? ""
        let transaction = claims["transactionId"] as? String ?? ""
        verified.withLock { $0 += 1 }
        let coins = StampPackCatalog.standard.definition(product)?.stamps ?? 0
        return .init(transactionID: transaction, productID: product, stamps: coins, balance: coins, duplicate: false)
    }

    private static func padded(_ base64URL: String) -> String {
        let base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
    }
}
#endif
