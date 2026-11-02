import Foundation
import Observation

/// The shop as screens use it: state that saves itself after every change, and the rewards the
/// app's own actions pay out.
@MainActor
@Observable
public final class ShopStore {
  /// The ledger ID of the one-off demo grant.
  public static let grantID = "grant:demo"

  public let catalog: ShopCatalog
  public private(set) var state: ShopState

  @ObservationIgnored private let storage: ShopStorage
  @ObservationIgnored private let makeID: @Sendable () -> String

  public init(
    catalog: ShopCatalog = .standard,
    storage: ShopStorage,
    grant: Int = ShopConfig.demoGrant,
    makeID: @escaping @Sendable () -> String = { UUID().uuidString }
  ) {
    self.catalog = catalog
    self.storage = storage
    self.makeID = makeID
    var loaded = storage.load() ?? ShopState()
    // Applied under one fixed ID, so every launch after the first leaves the balance alone.
    if loaded.credit(grant, as: .grant, id: Self.grantID) == .applied { storage.save(loaded) }
    state = loaded
  }

  public var stamps: Int { state.wallet.balance }

  public func owned(_ item: ShopItem) -> Int { state.closet.count(of: item.id) }

  /// A fresh transaction ID for one tap. A screen keeps it until the tap is resolved, so sending the
  /// same tap again cannot apply it twice.
  public func newTransaction() -> String { makeID() }

  @discardableResult
  public func buy(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.buy(item, transaction: transaction)
    }
  }

  @discardableResult
  public func place(
    _ item: ShopItem, transaction: String, at spot: (x: Double, z: Double)? = nil
  ) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.place(item, transaction: transaction, at: spot)
    }
  }

  @discardableResult
  public func remove(placement id: String, transaction: String) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.remove(placement: id, transaction: transaction)
    }
  }

  public func move(placement id: String, x: Double, z: Double, yaw: Double) throws(ShopError) {
    _ = try change { (state: inout ShopState) throws(ShopError) -> ShopOutcome in
      try state.move(placement: id, x: x, z: z, yaw: yaw)
      return .applied
    }
  }

  @discardableResult
  public func paint(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.paint(item, transaction: transaction)
    }
  }

  public func clearPaint(on surface: RoomSurface) {
    guard state.layout.material(on: surface) != nil else { return }
    var next = state
    next.clearPaint(on: surface)
    commit(next)
  }

  @discardableResult
  public func use(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.use(item, transaction: transaction)
    }
  }

  /// Takes a piece or a treat out of the closet to give to the partner.
  @discardableResult
  public func give(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.give(item, transaction: transaction)
    }
  }

  /// Puts a gift from the partner into the closet.
  @discardableResult
  public func receive(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    try change { (state: inout ShopState) throws(ShopError) in
      try state.receive(item, transaction: transaction)
    }
  }

  private func change(
    _ body: (inout ShopState) throws(ShopError) -> ShopOutcome
  ) throws(ShopError) -> ShopOutcome {
    var next = state
    let outcome = try body(&next)
    if outcome == .applied { commit(next) }
    return outcome
  }

  private func commit(_ next: ShopState) {
    state = next
    storage.save(next)
  }
}
