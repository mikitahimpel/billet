import Wire

/// A stamp or a seal for notes, as the Shop sells it: unlocked once for the pair and kept for good. `price` is in
/// coins. A note from the partner shows its stamp and seal whether or not this pair unlocked them.
public nonisolated struct NotePostage: Identifiable, Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case stamp(NoteStamp)
    case seal(NoteSeal)
  }

  public let kind: Kind
  public let price: Int

  public init(_ kind: Kind) {
    self.kind = kind
    switch kind {
    case .stamp: price = Self.stampPrice
    case .seal: price = Self.sealPrice
    }
  }

  public init(_ stamp: NoteStamp) { self.init(.stamp(stamp)) }
  public init(_ seal: NoteSeal) { self.init(.seal(seal)) }

  /// The catalog id, `stamp-<name>` or `seal-<name>`, also the key in the wallet's owned set.
  public var id: String { wireID.rawValue }

  public var wireID: PostageId {
    switch kind {
    case .stamp(let stamp): PostageId(stamp)
    case .seal(let seal): PostageId(seal)
    }
  }

  /// "Moon stamp", "Rose seal": the names the Design package's stamp and seal art show.
  public var name: String {
    switch kind {
    case .stamp(let stamp): "\(stamp.rawValue.capitalized) stamp"
    case .seal(let seal): "\(seal.rawValue.capitalized) seal"
    }
  }

  public func isOwned(_ owned: Set<String>) -> Bool { owned.contains(id) }

  /// As `packages/contracts/domain/src/postage.ts` prices them; the server charges its own.
  public static let stampPrice = 30
  public static let sealPrice = 45

  public static let stamps: [NotePostage] = NoteStamp.allCases.map(NotePostage.init)
  public static let seals: [NotePostage] = NoteSeal.allCases.map(NotePostage.init)
  public static let all: [NotePostage] = stamps + seals
}
