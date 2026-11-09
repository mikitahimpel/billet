import SwiftUI

/// Something the user did that the app counts, for the funnel in `docs/experiments.md`. Facts
/// only: which kind of thing, and the catalogue id of what it was done with. Never a note, a name
/// or any text the user wrote.
public enum AppEvent: Hashable, Sendable {
  public enum Food: Hashable, Sendable {
    /// The day's shared treat, which the streak counts.
    case treat
    /// Any other food, such as a treat from the closet.
    case food
  }

  public enum NoteSource: Hashable, Sendable {
    /// The app was opened from a widget showing the note.
    case widget
    /// The note was opened from a list or the desk in the app.
    case app
  }

  public enum WidgetButton: Hashable, Sendable {
    case pet
    case treat
  }

  case catPetted
  case catFed(Food)
  /// A game with the cat, with the toy when the game had one.
  case catPlayed(CatToy?)
  case catCalled
  case trickDone(CatTrick)
  case catChosen(CatModel)
  case temperamentShown(CatTemperament)
  case noteOpened(NoteSource)
  case decoratingOpened
  case roomItemPlaced(ShopItem.ID)
  case roomItemMoved(ShopItem.ID)
  case roomItemPutAway(ShopItem.ID)
  /// The walls, the floor or the window changed, with the material or setting it changed to.
  case roomCustomised(ShopItem.ID?)
  case shopOpened
  case shopItemViewed(ShopItem.ID)
  /// Bought for `price` stamps.
  case shopItemBought(ShopItem.ID, price: Int)
  /// One of the shop's offers came on screen: a bundle's id, or a deal's item.
  case shopOfferViewed(String)
  /// A bundle bought for `price` stamps.
  case shopBundleBought(String, price: Int)
  /// A purchase, of an item or a bundle by id, taken back, giving `stamps` back.
  case shopPurchaseUndone(String, stamps: Int)
  /// The day's free gift taken: so many stamps, or an item.
  case shopDailyGiftClaimed(DailyGift.Reward)
  /// An item bought for the partner for `price` stamps.
  case shopGiftSent(ShopItem.ID, price: Int)
  case streakOpened
  case streakMilestoneSeen(FlameStage)
  case widgetButtonTapped(WidgetButton)
  case profileOpened
  case signInPromptShown
  case signInPromptAnswered(accepted: Bool)
}

/// Where views report an ``AppEvent``. Hosts put one in the environment as
/// ``EnvironmentValues/appEvents``; the default records nothing, as a build without an account to
/// report to wants.
public struct AppEvents: Sendable {
  private let record: @MainActor @Sendable (AppEvent) -> Void

  public init(_ record: @escaping @MainActor @Sendable (AppEvent) -> Void) {
    self.record = record
  }

  @MainActor
  public func callAsFunction(_ event: AppEvent) {
    record(event)
  }

  public static let none = AppEvents { _ in }
}

extension EnvironmentValues {
  @Entry public var appEvents: AppEvents = .none
}

/// The room events between two layouts: a piece that appeared was placed, one that went was put
/// away, one that stands elsewhere or faces another way was moved, and a new wall or floor
/// material customised the room.
public enum RoomLayoutEvents {
  public static func between(_ old: RoomLayout, _ new: RoomLayout) -> [AppEvent] {
    let before = Dictionary(old.placements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let after = Dictionary(new.placements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var events: [AppEvent] = []
    for placement in new.placements {
      if let earlier = before[placement.id] {
        if earlier.x != placement.x || earlier.z != placement.z || earlier.yaw != placement.yaw {
          events.append(.roomItemMoved(placement.item))
        }
      } else {
        events.append(.roomItemPlaced(placement.item))
      }
    }
    for placement in old.placements where after[placement.id] == nil {
      events.append(.roomItemPutAway(placement.item))
    }
    for surface in RoomSurface.allCases {
      let material = new.material(on: surface)
      if let material, material != old.material(on: surface) {
        events.append(.roomCustomised(material))
      }
    }
    return events
  }
}
