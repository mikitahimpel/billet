import Foundation
import Payments
import SwiftUI
import Synchronization
import Transport
import Wire

/// The build's store as the demo app gets it from the app target, which alone knows whether it
/// is the mock or StoreKit (see `PaymentsLive`).
public struct DemoPayments: Sendable {
  public let payments: any Payments
  public let labs: (@MainActor @Sendable () -> AnyView)?

  public init(payments: any Payments, labs: (@MainActor @Sendable () -> AnyView)?) {
    self.payments = payments
    self.labs = labs
  }
}

/// The room the purchase routes are called for. Demo rooms have no session, so the dev server
/// takes the room code instead (`X-Billet-Demo-Room`).
final class DemoPaymentsCaller: Sendable {
  private let room = Mutex<String?>(nil)

  func set(_ code: String?) { room.withLock { $0 = code } }
  func current() -> String? { room.withLock { $0 } }
}

extension PaymentsServer {
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
              StampLedger.Entry(
                id: entry.id,
                kind: {
                  switch entry.kind {
                  case .purchase: .purchase
                  case .refund: .refund
                  }
                }(), amount: entry.amount, productID: entry.productId)
            })
        } catch {
          throw mapped(error)
        }
      })
  }

  private static func answer(_ response: PurchaseResponse) -> Answer {
    Answer(
      transactionID: response.transactionId, productID: response.productId,
      stamps: response.stamps, balance: response.balance, duplicate: response.duplicate)
  }

  private static func mapped(_ error: TransportError) -> PaymentsError {
    switch error {
    case .api(.invalidPurchase), .api(.invalidRequest): .rejected
    case .api(.unauthorized), .api(.notFound), .api(.unavailable), .api(.invalidInvite),
      .api(.alreadyPaired), .api(.appleIdInUse), .network, .status, .maintenance, .encoding,
      .decoding:
      .unavailable
    }
  }
}
