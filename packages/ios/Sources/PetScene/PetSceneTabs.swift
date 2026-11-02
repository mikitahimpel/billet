import CoreGraphics
import Foundation
import Pet

/// What the shop scene shows: the items on its shelves and who keeps the shop.
public struct ShopSceneState: Equatable, Sendable {
  public var items: [ShopItem]
  public var keeper: Shopkeeper
  /// Goes up by one for each thing bought, so the keeper can react to it.
  public var purchases: Int

  public init(items: [ShopItem], keeper: Shopkeeper = .standard, purchases: Int = 0) {
    self.items = items
    self.keeper = keeper
    self.purchases = purchases
  }
}

/// What the shop scene reports to its host.
public enum ShopSceneEvent: Hashable, Sendable {
  /// An item on a shelf, the counter or the paint table was tapped.
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
