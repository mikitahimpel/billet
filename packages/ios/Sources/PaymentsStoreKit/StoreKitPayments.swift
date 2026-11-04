import Foundation
import Payments
import StoreKit
import Synchronization

/// Payments through the App Store with StoreKit 2. A transaction is sent to the server as Apple
/// signed it, and finished only after the server has credited it, so a crash or a lost network in
/// between leaves it unfinished and it is sent again from ``Transaction/updates`` or
/// ``restore()``.
///
/// Refunds reach the server from Apple (App Store Server Notifications), not from the device; the
/// device only learns of them as a changed ledger.
public final class StoreKitPayments: Payments {
  private struct State {
    var subscribers: [UUID: AsyncStream<PaymentsUpdate>.Continuation] = [:]
    var listener: Task<Void, Never>?
  }

  private let catalog: StampPackCatalog
  private let server: PaymentsServer
  private let state = Mutex(State())

  public init(catalog: StampPackCatalog = .standard, server: PaymentsServer) {
    self.catalog = catalog
    self.server = server
  }

  deinit {
    state.withLock { $0.listener?.cancel() }
  }

  /// Starts listening to ``Transaction/updates``. Call once at launch, so purchases approved or
  /// finished elsewhere are credited.
  public func start() {
    state.withLock { state in
      guard state.listener == nil else { return }
      state.listener = Task.detached { [weak self] in
        for await result in Transaction.updates {
          await self?.handle(update: result)
        }
      }
    }
  }

  public func products() async throws(PaymentsError) -> [StampPack] {
    let products: [Product]
    do {
      products = try await Product.products(for: catalog.productIDs)
    } catch {
      throw .unavailable
    }
    return catalog.packs.compactMap { definition in
      guard let product = products.first(where: { $0.id == definition.id }) else { return nil }
      return StampPack(
        id: product.id, stamps: definition.stamps, displayName: product.displayName,
        description: product.description, displayPrice: product.displayPrice)
    }
  }

  public func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult {
    guard catalog.definition(pack.id) != nil else { throw .unknownProduct(pack.id) }
    guard AppStore.canMakePayments else { throw .notAllowed }
    let product: Product
    let result: Product.PurchaseResult
    do {
      guard let found = try await Product.products(for: [pack.id]).first else {
        throw PaymentsError.unknownProduct(pack.id)
      }
      product = found
      result = try await product.purchase()
    } catch let error as PaymentsError {
      throw error
    } catch StoreKitError.userCancelled {
      return .cancelled
    } catch {
      throw Self.mapped(error)
    }
    switch result {
    case .success(let verification):
      return .purchased(try await credit(verification))
    case .userCancelled:
      return .cancelled
    case .pending:
      return .pending
    @unknown default:
      throw .failed("The App Store answered a purchase result this build does not know.")
    }
  }

  public func restore() async throws(PaymentsError) -> StampLedger {
    for await result in Transaction.unfinished {
      _ = try? await credit(result)
    }
    return try await server.ledger()
  }

  public func updates() -> AsyncStream<PaymentsUpdate> {
    let (stream, continuation) = AsyncStream<PaymentsUpdate>.makeStream()
    let id = UUID()
    state.withLock { $0.subscribers[id] = continuation }
    continuation.onTermination = { [weak self] _ in
      _ = self?.state.withLock { $0.subscribers.removeValue(forKey: id) }
    }
    return stream
  }

  private func handle(update result: VerificationResult<Transaction>) async {
    let transaction = result.unsafePayloadValue
    guard catalog.definition(transaction.productID) != nil else { return }
    if transaction.revocationDate != nil {
      // The server learns of a refund from Apple; the device only follows its ledger.
      await transaction.finish()
      if let ledger = try? await server.ledger() { publish(.ledgerChanged(ledger)) }
      return
    }
    if let credit = try? await credit(result) { publish(.credited(credit)) }
  }

  /// Sends the transaction as Apple signed it and finishes it once the server has answered. The
  /// device's own verification is not trusted for money; the server checks the signature again.
  private func credit(_ result: VerificationResult<Transaction>) async throws(PaymentsError)
    -> StampCredit
  {
    let transaction = result.unsafePayloadValue
    if case .unverified = result {
      // Apple's signature does not check out on the device: the server would refuse it too.
      throw .rejected
    }
    let answer = try await server.verify(result.jwsRepresentation)
    await transaction.finish()
    return answer.credit
  }

  private func publish(_ update: PaymentsUpdate) {
    for continuation in state.withLock({ Array($0.subscribers.values) }) {
      continuation.yield(update)
    }
  }

  private static func mapped(_ error: any Error) -> PaymentsError {
    if let error = error as? StoreKitError {
      switch error {
      case .userCancelled: return .failed("cancelled")
      case .networkError: return .unavailable
      case .notAvailableInStorefront, .notEntitled: return .notAllowed
      case .systemError, .unknown, .unsupported: return .failed(String(describing: error))
      @unknown default: return .failed(String(describing: error))
      }
    }
    if let error = error as? Product.PurchaseError {
      switch error {
      case .purchaseNotAllowed: return .notAllowed
      case .productUnavailable: return .unavailable
      case .invalidQuantity, .ineligibleForOffer, .invalidOfferIdentifier, .invalidOfferPrice,
        .invalidOfferSignature, .missingOfferParameters:
        return .failed(String(describing: error))
      @unknown default: return .failed(String(describing: error))
      }
    }
    return .failed(String(describing: error))
  }
}
