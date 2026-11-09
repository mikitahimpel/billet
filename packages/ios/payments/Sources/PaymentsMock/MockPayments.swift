import Foundation
import Payments
import Synchronization

/// Nothing here talks to Apple: the dev server credits through `POST /v1/purchases/mock`.
/// ``MockSwitches`` makes the next purchase cancel, fail or wait for Ask to Buy.
public final class MockPayments: Payments {
  private struct State {
    var subscribers: [UUID: AsyncStream<PaymentsUpdate>.Continuation] = [:]
    var pending: [String: StampPack] = [:]
    var lastPurchase: (transactionID: String, productID: String)?
  }

  private let catalog: StampPackCatalog
  private let server: PaymentsServer
  private let switches: MockSwitches
  private let makeID: @Sendable () -> String
  private let state = Mutex(State())

  public init(
    catalog: StampPackCatalog = .standard,
    server: PaymentsServer,
    switches: MockSwitches,
    makeID: @escaping @Sendable () -> String = { "mock-\(UUID().uuidString.lowercased())" }
  ) {
    self.catalog = catalog
    self.server = server
    self.switches = switches
    self.makeID = makeID
  }

  public func products() async throws(PaymentsError) -> [StampPack] {
    catalog.packs.map(catalog.pack)
  }

  public func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult {
    guard catalog.definition(pack.id) != nil else { throw .unknownProduct(pack.id) }
    switch switches.outcome {
    case .succeed:
      return .purchased(try await credit(pack, transactionID: makeID()))
    case .cancel:
      return .cancelled
    case .fail:
      throw .failed("The mock store failed this purchase (Labs → Payments).")
    case .pending:
      let id = makeID()
      state.withLock { $0.pending[id] = pack }
      return .pending
    }
  }

  public func restore() async throws(PaymentsError) -> StampLedger {
    try await server.ledger()
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

  public var pendingCount: Int { state.withLock { $0.pending.count } }

  /// Each is credited and announced on ``updates()``.
  public func approvePending() async throws(PaymentsError) {
    let waiting = state.withLock {
      let waiting = $0.pending
      $0.pending = [:]
      return waiting
    }
    for (id, pack) in waiting.sorted(by: { $0.key < $1.key }) {
      let credit = try await credit(pack, transactionID: id)
      publish(.credited(credit))
    }
  }

  public func declinePending() {
    state.withLock { $0.pending = [:] }
  }

  /// Refunds on the server, as Apple would, and announces the new ledger.
  @discardableResult
  public func refundLast() async throws(PaymentsError) -> Bool {
    guard let last = state.withLock({ $0.lastPurchase }) else { return false }
    _ = try await server.mock(last.productID, last.transactionID, .refund)
    state.withLock { $0.lastPurchase = nil }
    publish(.ledgerChanged(try await server.ledger()))
    return true
  }

  private func credit(_ pack: StampPack, transactionID: String) async throws(PaymentsError)
    -> StampCredit
  {
    let answer = try await server.mock(pack.id, transactionID, .purchase)
    state.withLock { $0.lastPurchase = (transactionID, pack.id) }
    return answer.credit
  }

  private func publish(_ update: PaymentsUpdate) {
    for continuation in state.withLock({ Array($0.subscribers.values) }) {
      continuation.yield(update)
    }
  }
}
