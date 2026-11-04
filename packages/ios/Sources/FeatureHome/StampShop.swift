import Foundation
import Observation
import Payments
import Pet

/// Stamp packs for money, as the shop uses them: the packs on sale, one purchase at a time, and
/// the pair's wallet kept in step with the server's ledger. Knows ``Payments`` only, never
/// StoreKit, so the same model serves the mock and the App Store builds.
@MainActor
@Observable
public final class StampShop {
  public enum State: Hashable, Sendable {
    case idle
    case loading
    case buying(StampPack.ID)
    /// Waiting for Ask to Buy. The stamps arrive later on their own.
    case pending
    case bought(StampCredit)
    case failed(String)
  }

  public private(set) var packs: [StampPack] = []
  public private(set) var state: State = .idle

  @ObservationIgnored private let payments: any Payments
  @ObservationIgnored private var shop: ShopStore?
  @ObservationIgnored private var listener: Task<Void, Never>?

  public init(payments: any Payments) {
    self.payments = payments
  }

  /// The wallet purchases go to. The shop changes when the pair (or the fake partner) does.
  public func attach(_ shop: ShopStore?) {
    guard self.shop !== shop else { return }
    self.shop = shop
    listener?.cancel()
    guard shop != nil else { return }
    let updates = payments.updates()
    listener = Task { [weak self] in
      for await update in updates {
        self?.apply(update)
      }
    }
    Task { await sync() }
  }

  /// Loads the packs with the store's prices.
  public func load() async {
    guard packs.isEmpty else { return }
    state = .loading
    do {
      packs = try await payments.products()
      state = .idle
    } catch {
      state = .failed(Self.message(for: error))
    }
  }

  /// Settles unfinished transactions and merges the server's ledger into the wallet.
  public func sync() async {
    guard let ledger = try? await payments.restore() else { return }
    apply(ledger)
  }

  public func buy(_ pack: StampPack) async {
    guard !isBuying else { return }
    state = .buying(pack.id)
    do {
      switch try await payments.purchase(pack) {
      case .purchased(let credit):
        apply(credit)
        state = .bought(credit)
      case .cancelled:
        state = .idle
      case .pending:
        state = .pending
      }
    } catch {
      state = .failed(Self.message(for: error))
    }
  }

  public var isBuying: Bool {
    if case .buying = state { return true }
    return false
  }

  private func apply(_ update: PaymentsUpdate) {
    switch update {
    case .credited(let credit):
      apply(credit)
      if state == .pending { state = .bought(credit) }
    case .ledgerChanged(let ledger):
      apply(ledger)
    }
  }

  private func apply(_ credit: StampCredit) {
    _ = shop?.creditPurchase(credit.stamps, id: credit.entryID)
  }

  /// Purchases the wallet has not seen are credited; refunds are taken back, never below zero.
  private func apply(_ ledger: StampLedger) {
    guard let shop else { return }
    for entry in ledger.entries {
      switch entry.kind {
      case .purchase:
        _ = shop.creditPurchase(entry.amount, id: entry.id)
      case .refund:
        _ = shop.revokePurchase(-entry.amount, id: Self.revokedID(for: entry.id))
      }
    }
  }

  /// The wallet's ID for an App Store refund: `revoked:<transaction>`. The shop's own `refund:`
  /// entries are stamps given back for an undone item.
  static func revokedID(for serverID: String) -> String {
    let transaction = serverID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? serverID
    return "revoked:\(transaction)"
  }

  private static func message(for error: PaymentsError) -> String {
    switch error {
    case .notAllowed: "Purchases are turned off on this iPhone."
    case .unavailable: "The store can't be reached right now. Try again in a moment."
    case .failed: "The purchase didn't go through. You weren't charged."
    case .rejected: "The purchase couldn't be checked. Contact us if you were charged."
    case .unknownProduct: "That pack isn't on sale any more."
    }
  }
}
