import CoreGraphics
import Foundation
import Pet

/// What the shop scene shows: the items on its shelves and who keeps the shop.
public struct ShopSceneState: Equatable, Sendable {
  public var items: [ShopItem]
  public var keeper: Shopkeeper
  /// Goes up by one for each thing bought, so the keeper can hand it over.
  public var purchases: Int
  /// The item brought forward to look at and buy, if any.
  public var focused: ShopItem.ID?
  /// Items that are owned and can only be owned once, whose tags say so instead of a price.
  public var owned: Set<ShopItem.ID>

  public init(
    items: [ShopItem], keeper: Shopkeeper = .standard, purchases: Int = 0,
    focused: ShopItem.ID? = nil, owned: Set<ShopItem.ID> = []
  ) {
    self.items = items
    self.keeper = keeper
    self.purchases = purchases
    self.focused = focused
    self.owned = owned
  }
}

/// What the shop scene reports to its host.
public enum ShopSceneEvent: Hashable, Sendable {
  /// An item on a shelf, the counter or the paint table, or its price tag, was tapped.
  case picked(ShopItem.ID)
}

/// A note pinned on the desk's board.
public struct DeskNote: Identifiable, Equatable, @unchecked Sendable {
  public let id: UUID
  /// The drawing on its paper. `CGImage` is immutable, so sharing it is safe.
  public let image: CGImage
  public let isReceived: Bool

  public init(id: UUID, image: CGImage, isReceived: Bool) {
    self.id = id
    self.image = image
    self.isReceived = isReceived
  }

  public static func == (lhs: DeskNote, rhs: DeskNote) -> Bool {
    lhs.id == rhs.id && lhs.image === rhs.image && lhs.isReceived == rhs.isReceived
  }
}

/// What the desk scene shows: the board's notes, newest first.
public struct DeskSceneState: Equatable, Sendable {
  public var notes: [DeskNote]

  public init(notes: [DeskNote]) {
    self.notes = notes
  }
}

/// What the desk scene reports to its host.
public enum DeskSceneEvent: Hashable, Sendable {
  /// The blank paper on the desk was tapped: time to draw.
  case paperTapped
  /// A note on the board was tapped.
  case noteTapped(UUID)
}

/// What the streak's flame scene shows: the flame for the pair's streak, who added to it today,
/// and what is new since this phone last opened it.
public struct FlameSceneState: Equatable, Sendable {
  public var flame: StreakFlame
  public var today: FlameContributions
  public var visit: FlameVisit

  public init(flame: StreakFlame, today: FlameContributions = .init(), visit: FlameVisit = .quiet) {
    self.flame = flame
    self.today = today
    self.visit = visit
  }
}

/// What the flame scene reports to its host.
public enum FlameSceneEvent: Hashable, Sendable {
  /// A finger came down on the flame, for a soft tap of feedback.
  case touched
  /// The once-only celebration or the rekindling burst began.
  case celebrated
}
