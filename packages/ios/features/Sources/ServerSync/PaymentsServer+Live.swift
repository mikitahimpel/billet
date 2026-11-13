import Foundation
import Payments
import Transport
import Wire

nonisolated extension PaymentsServer {
  /// The purchase routes on `client`, as plain values.
  public static func live(_ client: PurchasesClient) -> PaymentsServer {
    PaymentsServer(
      verify: { (jws) async throws(PaymentsError) in
        do throws(TransportError) {
          return answer(try await client.purchase(PurchaseRequest(signedTransaction: jws)))
        } catch {
          throw mapped(error)
        }
      },
      mock: { (product, transaction, kind) async throws(PaymentsError) in
        let wireKind: MockPurchaseRequest.Kind =
          switch kind {
          case .purchase: .purchase
          case .refund: .refund
          }
        do throws(TransportError) {
          return answer(
            try await client.mockPurchase(
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
              let kind: StampLedger.Kind =
                switch entry.kind {
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

  public static func mapped(_ error: TransportError) -> PaymentsError {
    switch error {
    case .api(.invalidPurchase), .api(.invalidRequest): .rejected
    case .api(.unauthorized), .api(.notFound), .api(.unavailable), .network, .status, .maintenance:
      .unavailable
    case .api(.invalidInvite), .api(.alreadyPaired), .api(.appleIdInUse), .api(.inkNotOwned),
      .api(.notEnoughCoins), .api(.alreadyOwned), .api(.collectionIncomplete), .api(.giftTaken),
      .api(.bonusTaken), .api(.catNotAdopted), .api(.streakNotRestorable), .api(.priceChanged),
      .api(.layoutRefused), .encoding,
      .decoding:
      .failed("The server answered something unexpected.")
    }
  }
}
