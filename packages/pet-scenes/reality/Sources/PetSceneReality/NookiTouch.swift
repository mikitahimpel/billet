import Foundation
import Pet
import PetScene

/// What a tap can land on. The raw value is the name of the entity that holds the collider.
enum NookiTarget: String, CaseIterable {
  case mochi
  case lamp
  case note
  case plant
  case bookcase
  case bed
}

/// What a tap does: the scene's own reaction, and the event it reports, if any.
struct NookiTouch: Equatable {
  enum Reaction: Equatable {
    case wakeAndHop
    case toggleLamp
    case toggleNote
    case wobble(NookiTarget)
  }

  var reaction: Reaction
  var event: PetSceneEvent?

  static func of(_ target: NookiTarget, world: PetWorld, noteIsOpen: Bool) -> NookiTouch {
    switch target {
    case .mochi:
      return NookiTouch(reaction: .wakeAndHop, event: .petted)
    case .lamp:
      return NookiTouch(reaction: .toggleLamp)
    case .note:
      return NookiTouch(
        reaction: .toggleNote,
        event: noteIsOpen ? nil : .noteOpened(delivery: world.delivery))
    case .plant, .bookcase, .bed:
      return NookiTouch(reaction: .wobble(target))
    }
  }
}

/// Tells a double tap from two taps. Single taps act at once, so nothing waits to see if a second
/// one comes.
struct NookiTapTimer {
  static let window: TimeInterval = 0.35

  private var lastTap: TimeInterval?

  mutating func isDoubleTap(at time: TimeInterval) -> Bool {
    if let lastTap, time - lastTap <= Self.window {
      self.lastTap = nil
      return true
    }
    lastTap = time
    return false
  }
}

extension PetPlayState.Treat {
  /// How full the bowl is, from 0 to 1. One partner's treat fills it halfway.
  var bowlFill: Float {
    switch self {
    case .neither: 0
    case .waitingOnPartner, .waitingOnMe: 0.5
    case .fed: 1
    }
  }
}
