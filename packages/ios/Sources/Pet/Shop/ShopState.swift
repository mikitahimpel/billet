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
  static func spendID(_ transaction: String) -> String { "spend:\(transaction)" }

  /// Pays for `item` and puts it in the closet. Nothing changes if it cannot be paid for.
  public mutating func buy(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    if item.ownsAtMostOne, owns(item) { throw .alreadyOwned }
    try wallet.debit(item.price, id: Self.spendID(transaction))
    closet.add(item.id)
    applied.insert(transaction)
    return .applied
  }

  /// Takes a piece of furniture out of the closet and stands it in the room. Without a spot it
  /// goes to the first open one, and throws when none is left.
  public mutating func place(
    _ item: ShopItem, transaction: String, at spot: (x: Double, z: Double)? = nil
  ) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    guard case .furniture(_, _, let mount) = item.look else { throw .wrongKind }
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
  public mutating func paint(_ item: ShopItem, transaction: String) throws(ShopError) -> ShopOutcome {
    guard !applied.contains(transaction) else { return .duplicate }
    guard case .material(let surface, _) = item.look else { throw .wrongKind }
    guard owns(item) else { throw .notInCloset }
    layout.paint(surface, with: item.id)
    applied.insert(transaction)
    return .applied
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

  /// Whether the pair has `item`, in the closet or, for a material, painted on a surface.
  public func owns(_ item: ShopItem) -> Bool {
    closet.count(of: item.id) > 0 || layout.wall == item.id || layout.floor == item.id
  }
}
