import Foundation
import GamesInterface
import Pet

/// What happened in the room that the rest of the app acts on. The room writes to no store itself.
public enum RoomEvent: Equatable, Sendable {
  case catPetted
  /// A card on the board was tapped; it opens as a sheet.
  case pinOpened(UUID)
  /// The board's pencil was tapped: the couple wants to doodle.
  case drawAsked
  /// Back after hours away, and the partner cared for the cat meanwhile: what they did, oldest first. Sent once per
  /// homecoming, when the pair's journal has caught up.
  case partnerCared([LifeEvent])
}

/// The room's commands. Every way in, apart from the host's input value.
@MainActor
public protocol RoomControlling: AnyObject {
  /// Taps and cat events, as they happen. One listener.
  var events: AsyncStream<RoomEvent> { get }
  /// A pet landed, from a tap, a widget or a treat: the cat purrs.
  func purr()
  /// A treat was bought: the cat ate.
  func feed()
  func appOpened()
  func play(_ game: MiniGame)
  func endGame()
  /// Plays every animation in turn, naming each.
  func playAll()
}

/// The cat as the screens outside the room see her: coarse, and changed at most once a second.
public struct CatStatus: Equatable, Sendable {
  /// Nil until her brain is running.
  public var needs: PetNeeds?
  public var mind: CatMind?

  public init(needs: PetNeeds? = nil, mind: CatMind? = nil) {
    self.needs = needs
    self.mind = mind
  }

  /// `needs` rounded to twentieths, so a small drift changes nothing outside the room.
  public init(rounding needs: PetNeeds?, mind: CatMind?) {
    let rounded = needs.map { needs in
      var out = needs
      for need in PetNeed.allCases { out[need] = (needs[need] * 20).rounded() / 20 }
      return out
    }
    self.init(needs: rounded, mind: mind)
  }
}

@MainActor
public protocol CatStatusProviding: AnyObject {
  var status: CatStatus { get }
}
