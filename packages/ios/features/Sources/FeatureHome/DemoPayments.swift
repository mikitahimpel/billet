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

/// The demo app's stamp packs: the build's store over the demo server's purchase routes, the
/// model the shop uses, and the room purchases are for. Built once, by the app at launch, since a
/// store listens for transactions for as long as it lives.
@MainActor
public final class DemoPaymentsSetup {
  let stampShop: StampShop
  let labs: (@MainActor @Sendable () -> AnyView)?
  let caller: DemoPaymentsCaller

  /// `nil` without a demo host: there is no server to credit purchases.
  public init?(host: String, make: (PaymentsServer) -> DemoPayments) {
    guard let baseURL = ServiceStatusModel.demoBaseURL(host: host) else { return nil }
    let caller = DemoPaymentsCaller()
    let built = make(
      .live(
        .live(
          http: .urlSession(
            baseURL: baseURL, session: .shared, headers: ClientInfo.current().headers),
          caller: .demoRoom { caller.current() })))
    self.caller = caller
    stampShop = StampShop(payments: built.payments)
    labs = built.labs
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
      .api(.alreadyPaired), .api(.appleIdInUse), .api(.inkNotOwned), .network, .status,
      .api(.notEnoughCoins), .api(.alreadyOwned),
      .maintenance, .encoding, .decoding:
      .unavailable
    }
  }
}
