import Foundation

/// Everything the shop keeps, and the only place its rules live.
///
/// Every change names a transaction ID. The same ID applied twice changes nothing the second time,
/// so a tap delivered again after a reconnect, or a reward seen on two launches, counts once.
public struct ShopState: Codable, Hashable, Sendable {
  public private(set) var wallet: StampWallet
  public private(set) var closet: Closet
  public private(set) var layout: RoomLayout
  /// Counts up each time a treat is used, so a scene can react to each use.
  public private(set) var treatsUsed: Int
  public private(set) var lastTreat: ShopItem.ID?
  private var applied: Set<String>

  public init() {
    wallet = StampWallet()
    closet = Closet()
    layout = RoomLayout()
    treatsUsed = 0
    lastTreat = nil
    applied = []
  }

  public func hasApplied(_ transaction: String) -> Bool {
    applied.contains(transaction)
  }

  /// Adds stamps to the wallet as a ledger entry with a unique `id`.
  public mutating func credit(
    _ amount: Int, as credit: StampWallet.Credit, id: String
  ) -> ShopOutcome {
    wallet.credit(amount, as: credit, id: id)
  }

  /// The ledger ID of the entry a purchase transaction writes.
  /// Takes back bought stamps after an App Store refund. See ``StampWallet/revoke(_:id:)``.
  public mutating func revoke(_ amount: Int, id: String) -> Int? {
    wallet.revoke(amount, id: id)
  }

  static func spendID(_ transaction: String) -> String { "spend:\(transaction)" }

  /// Pays for `item` and puts it in the closet. Nothing changes if it cannot be paid for.
  public mutating func buy(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    if item.ownsAtMostOne, owns(item) { throw .alreadyOwned }
    _ = try wallet.debit(item.price, id: Self.spendID(transaction))
    closet.add(item.id)
    applied.insert(transaction)
    return .applied
  }

  /// Takes back the purchase made under `transaction`: the item leaves the room and the closet,
  /// and its stamps go back to the wallet. `placement` is where the purchase was stood in the room,
  /// if it was. Nothing changes when any of that cannot be done, such as a treat already used.
  public mutating func undoBuy(
    _ item: ShopItem, transaction: String, placement: RoomLayout.Placement.ID? = nil
  ) throws(ShopError) -> ShopOutcome {
    let undo = Self.undoID(transaction)
    guard !applied.contains(undo) else { return .duplicate }
    let spendID = Self.spendID(transaction)
    guard applied.contains(transaction),
      let spent = wallet.entries.first(where: { $0.id == spendID })
    else { throw .unknownPurchase }
    var next = self
    if let placement, next.layout.placements.contains(where: { $0.id == placement }) {
      let removed = try next.layout.remove(placement)
      next.closet.add(removed.item)
    }
    try next.closet.take(item.id)
    _ = next.wallet.credit(-spent.amount, as: .refund, id: Self.refundID(transaction))
    next.applied.insert(undo)
    self = next
    return .applied
  }

  static func undoID(_ transaction: String) -> String { "undo:\(transaction)" }
  static func refundID(_ transaction: String) -> String { "refund:\(transaction)" }

  /// Takes a piece of furniture out of the closet and stands it in the room. Without a spot it
  /// goes to the first open one, and throws when none is left.
  public mutating func place(
    _ item: ShopItem, transaction: String, at spot: (x: Double, z: Double)? = nil
  ) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    guard case .furniture(_, _, _, let mount) = item.look else { throw .wrongKind }
    guard closet.count(of: item.id) > 0 else { throw .notInCloset }
    guard let target = spot ?? layout.freeSpot(for: mount) else { throw .roomIsFull }
    try closet.take(item.id)
    layout.add(.init(id: "placed-\(transaction)", item: item.id, x: target.x, z: target.z))
    applied.insert(transaction)
    return .applied
  }

  /// Takes a placed piece out of the room and back into the closet.
  public mutating func remove(
    placement id: RoomLayout.Placement.ID, transaction: String
  ) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    let removed = try layout.remove(id)
    closet.add(removed.item)
    applied.insert(transaction)
    return .applied
  }

  /// Moves a placed piece. Moving costs nothing and asks nothing of the closet.
  public mutating func move(
    placement id: RoomLayout.Placement.ID, x: Double, z: Double, yaw: Double
  ) throws(ShopError) {
    try layout.move(id, x: x, z: z, yaw: yaw)
  }

  /// Puts an owned material on a wall or the floor. The material stays owned.
  public mutating func paint(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome
  {
    guard !applied.contains(transaction) else { return .duplicate }
    guard case .material(let surface, _) = item.look else { throw .wrongKind }
    guard owns(item) else { throw .notInCloset }
    layout.paint(surface, with: item.id)
    applied.insert(transaction)
    return .applied
  }

  /// Bares a surface. The material stays owned.
  public mutating func clearPaint(on surface: RoomSurface) {
    layout.paint(surface, with: nil)
  }

  /// Uses one treat up.
  public mutating func use(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    guard item.isConsumable else { throw .wrongKind }
    try closet.take(item.id)
    treatsUsed += 1
    lastTreat = item.id
    applied.insert(transaction)
    return .applied
  }

  /// Takes `item` out of the closet to give it away. Only a piece or a treat can be given: a
  /// material is painted on, not wrapped.
  public mutating func give(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome
  {
    guard !applied.contains(transaction) else { return .duplicate }
    guard !item.ownsAtMostOne else { throw .wrongKind }
    try closet.take(item.id)
    applied.insert(transaction)
    return .applied
  }

  /// Puts a gifted `item` into the closet, without a price.
  public mutating func receive(_ item: ShopItem, transaction: String) throws(ShopError)
    -> ShopOutcome
  {
    guard !applied.contains(transaction) else { return .duplicate }
    guard !item.ownsAtMostOne else { throw .wrongKind }
    closet.add(item.id)
    applied.insert(transaction)
    return .applied
  }

  /// Whether the pair has `item`, in the closet or, for a material, painted on a surface.
  public func owns(_ item: ShopItem) -> Bool {
    closet.count(of: item.id) > 0 || layout.wall == item.id || layout.floor == item.id
  }
}
