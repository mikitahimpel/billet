import Foundation
import Payments
import PaymentsLive
import Transport
import Wire

// BILLET_PAYMENTS picks the store when the app is built (docs/payments.md). The target turns it into PAYMENTS_MOCK or
// PAYMENTS_STOREKIT, and Package.swift links only the matching store into PaymentsLive. Each branch names a type that
// exists in its own mode only, so an app and a package resolved for different modes fail to build.
#if PAYMENTS_STOREKIT
private typealias Build = StoreKitPaymentsBuild
#elseif PAYMENTS_MOCK
private typealias Build = MockPaymentsBuild
#else
#error("BILLET_PAYMENTS must be mock or storekit.")
#endif

enum AppPayments {
    /// A mock build fakes the store and the dev server credits it, so it sells coin packs whatever the `payments`
    /// flag says; a StoreKit build sells them only once the server turned the flag on.
    #if PAYMENTS_MOCK
    static let isMock = true
    #else
    static let isMock = false
    #endif

    /// The build's store over the pair's purchase routes, listening for transactions from launch on.
    static func make(_ client: PurchasesClient) -> any Payments {
        let live = Build.make(server: .live(client), defaults: .standard)
        live.start()
        return live.payments
    }
}

nonisolated extension PaymentsServer {
    /// The purchase routes on `client`, as plain values.
    static func live(_ client: PurchasesClient) -> PaymentsServer {
        PaymentsServer(
            verify: { (jws) async throws(PaymentsError) in
                do throws(TransportError) {
                    return answer(try await client.purchase(PurchaseRequest(signedTransaction: jws)))
                } catch {
                    throw mapped(error)
                }
            },
            mock: { (product, transaction, kind) async throws(PaymentsError) in
                let wireKind: MockPurchaseRequest.Kind = switch kind {
                case .purchase: .purchase
                case .refund: .refund
                }
                do throws(TransportError) {
                    return answer(try await client.mockPurchase(
                        MockPurchaseRequest(productId: product, transactionId: transaction, kind: wireKind)))
                } catch {
                    throw mapped(error)
                }
            },
            ledger: { () async throws(PaymentsError) in
                do throws(TransportError) {
                    let response = try await client.stamps()
                    return StampLedger(
                        balance: response.balance,
                        entries: response.entries.map { entry in
                            let kind: StampLedger.Kind = switch entry.kind {
                            case .purchase: .purchase
                            case .refund: .refund
                            }
                            return StampLedger.Entry(
                                id: entry.id, kind: kind, amount: entry.amount, productID: entry.productId)
                        })
                } catch {
                    throw mapped(error)
                }
            })
    }

    private static func answer(_ response: PurchaseResponse) -> Answer {
        Answer(
            transactionID: response.transactionId, productID: response.productId, stamps: response.stamps,
            balance: response.balance, duplicate: response.duplicate)
    }

    static func mapped(_ error: TransportError) -> PaymentsError {
        switch error {
        case .api(.invalidPurchase), .api(.invalidRequest): .rejected
        case .api(.unauthorized), .api(.notFound), .api(.unavailable), .network, .status, .maintenance: .unavailable
        case .api(.invalidInvite), .api(.alreadyPaired), .api(.appleIdInUse), .api(.inkNotOwned),
             .api(.notEnoughCoins), .api(.alreadyOwned), .api(.collectionIncomplete), .api(.giftTaken),
             .api(.bonusTaken), .api(.catNotAdopted), .encoding, .decoding:
            .failed("The server answered something unexpected.")
        }
    }
}
