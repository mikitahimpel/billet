import Foundation

/// Something in the room the cat can use: a window to watch from, a bowl, a soft heap to sit in.
public struct RoomAffordance: Codable, Hashable, Sendable, Identifiable {
  public enum Kind: String, CaseIterable, Codable, Hashable, Sendable {
    case window
    /// A patch of sun under the window, there only by day.
    case sunbeam
    case rug
    case bowl
    /// A cat bed or a daybed.
    case bed
    /// A crate or a box to sit in.
    case box
    /// A shelf up high.
    case shelf
    /// Clothes left out: a cardigan, a hoodie, a jumper on a chair.
    case soft
    /// A mug or a phone small enough to nudge, never far enough to fall.
    case smallItem
    case desk
    case door
    case toy
    /// A placed sofa, armchair or bean bag: a soft seat to curl up on.
    case sofa
    /// A placed window seat, a seat at a window.
    case windowSeat
    /// A placed scratching post.
    case scratchingPost
    /// A placed cat bed.
    case catBed
    /// A placed box or tunnel to sit in.
    case crate
  }

  /// Stable across phones: a piece's kind and place, or a shop placement's ID.
  public let id: String
  public let kind: Kind
  /// Whether the cat can get to it from its own surface. Out of reach, it can still be watched.
  public let reachable: Bool
  /// When it appeared in the room, in seconds since 1970, if known. A piece seen for the first
  /// time is something to inspect.
  public let since: Double?

  public init(id: String, kind: Kind, reachable: Bool = true, since: Double? = nil) {
    self.id = id
    self.kind = kind
    self.reachable = reachable
    self.since = since
  }
}

/// What the room offers the cat, as both phones see it. The brain only reads kinds and IDs; the
/// scene finds where each one stands.
public struct RoomAffordances: Codable, Hashable, Sendable {
  /// Sorted by ID, so every phone walks them in the same order.
  public let all: [RoomAffordance]

  public init(_ affordances: some Sequence<RoomAffordance>) {
    var seen = Set<String>()
    all = affordances.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
  }

  public static let empty = RoomAffordances([])

  public func has(_ kind: Kind) -> Bool { all.contains { $0.kind == kind } }

  public func reachable(_ kind: Kind) -> Bool {
    all.contains { $0.kind == kind && $0.reachable }
  }

  public func first(_ kind: Kind) -> RoomAffordance? {
    all.first { $0.kind == kind && $0.reachable }
  }

  /// The reachable pieces of furniture the cat could inspect, newest placement last.
  public var furniture: [RoomAffordance] {
    all.filter {
      $0.reachable
        && [.bed, .box, .shelf, .soft, .desk, .rug, .sofa, .windowSeat, .catBed, .crate]
          .contains($0.kind)
    }
  }

  public typealias Kind = RoomAffordance.Kind
}

extension RoomAffordance.Kind {
  /// The place in a few words, as in "Favourite spot: the windowsill"; nil for a thing she uses
  /// but does not stay at.
  public func spotName(for pronouns: CatPronouns) -> String? {
    switch self {
    case .window: "The windowsill"
    case .sunbeam: "The patch of sun"
    case .rug: "The rug"
    case .bed, .catBed: pronouns.say(.bedSpot)
    case .box, .crate: pronouns.say(.boxSpot)
    case .shelf: "The top shelf"
    case .soft: "Your cardigan"
    case .desk: "The desk"
    case .sofa: "The sofa"
    case .windowSeat: "The window seat"
    case .scratchingPost: "The scratching post"
    case .bowl, .smallItem, .door, .toy: nil
    }
  }
}
