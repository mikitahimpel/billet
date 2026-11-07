import Foundation

/// Everything a cat model can be asked to do. The raw values are the clip names in each model's
/// clip table, so a model without one of these simply never plays it.
public enum CatAction: String, CaseIterable, Codable, Hashable, Sendable {
  case idle
  case walk
  case sit
  case sleep
  case crouchWiggle
  case pounce
  case eat
  case blink
  case look
  case tailFlick
  case happy
  case stretch
  case yawn
  case groom
  case knead
  case slowBlink
  case perk
  /// Asleep, an ear flicks, the tail tip curls and a hind paw flexes.
  case twitch
  /// From sitting, onto its back with the belly up, and up again.
  case rollOver
  /// From sitting, a forepaw swats at something twice.
  case bat
  /// Standing, the top of the head bumps forward, then a cheek rub.
  case headbutt
  /// Standing, it rears up and presses both forepaws on the wall.
  case reachUp
  /// On its back under a hand, it hugs the hand with its forepaws and bunny-kicks.
  case grab
  /// Standing, nose forward, it sniffs at something held out.
  case sniff
  /// Sitting, one forepaw lifts and waves.
  case wave
  /// Held up under the forelegs, the hind legs and tail hang loose.
  case dangle
  /// Lying like a loaf: paws tucked under, eyes open, breathing slowly. A loop in its own base.
  case loaf
  /// A gallop in place, for chases and zoomies. Travel at `NookiClip.runningSpeed` keeps the paws
  /// planted.
  case run
  /// From standing, noses round to pick a spot and settles into the sleeping curl. Starts in
  /// `stand` and ends in `sleep` (`CatClipInfo.ends`).
  case lieDown
  /// Sitting, the head turns right round to lick the right flank.
  case groomFlank
  /// Sitting, the tail comes round in front, pinned by a forepaw, and is licked.
  case groomTail
  /// Sitting, two quick flicks of the mouth with the chin up, as after eating.
  case lickLips
  /// Standing, a fright: the back arches, it springs back a little with the tail up and ears flat.
  case startle
  /// Sitting, ears forward, the head tilts over to one side and then a little to the other.
  case headTilt
  /// The walk with a toy in the mouth, head up and tail proud. Travels like the walk.
  case carry
  /// Standing, leans into something on its left, cheek first, then shoulder and flank.
  case rubSide
  /// Sitting, watching something high up with the head well back. A loop.
  case lookUp
  /// Gathers, springs up and forward, lands. Airborne from `CatClipInfo.jumpAir`'s start to its
  /// end, as shares of the clip; the room carries the cat along the arc in between.
  case jumpUp
  /// Gathers, springs, reaches down with the forepaws and lands. Airborne as `jumpUp`.
  case jumpDown

  /// The moves to play instead, in order, for a model without this clip.
  public var standIns: [CatAction] {
    switch self {
    case .rollOver: [.happy, .slowBlink]
    case .bat: [.perk, .look]
    case .headbutt: [.happy, .perk]
    case .reachUp: [.perk, .stretch, .idle]
    case .grab: [.bat, .rollOver]
    case .sniff: [.look, .perk]
    case .wave: [.bat, .perk]
    case .dangle: [.stretch, .idle]
    case .loaf: [.sit]
    case .run: [.walk]
    case .lieDown: [.sleep]
    case .groomFlank, .groomTail: [.groom]
    case .lickLips: [.happy]
    case .startle, .headTilt: [.perk]
    case .carry: [.walk]
    case .rubSide: [.headbutt, .happy]
    case .lookUp: [.look, .sit]
    case .jumpUp, .jumpDown: [.pounce]
    case .idle, .walk, .sit, .sleep, .crouchWiggle, .pounce, .eat, .blink, .look, .tailFlick,
      .happy, .stretch, .yawn, .groom, .knead, .slowBlink, .perk, .twitch:
      []
    }
  }
}
