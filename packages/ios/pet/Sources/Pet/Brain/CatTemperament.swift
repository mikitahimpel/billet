import Foundation

/// What kind of cat this one is at heart: picked once when the couple adopts it and never changed.
/// It sets the cat's nature (the traits experience later moves a little), which activities it
/// leans to, how lively it moves, how close it comes to a finger and how it answers a touch.
///
/// Five types, each a corner of the trait axes bold–shy, energetic–lazy, cuddly–independent,
/// curious–cautious and vocal–quiet. They differ enough to tell apart within half a minute.
public enum CatTemperament: String, CaseIterable, Codable, Hashable, Sendable {
  /// Cuddly, vocal, easy-going: comes to the camera, rubs, slow-blinks, purrs at a look.
  case cuddler
  /// Curious and bold: wanders, sniffs, inspects every new piece, watches the window.
  case explorer
  /// Bold, vocal and independent: grooms, takes the best spot, comes when it wants to.
  case diva
  /// Lazy and gentle: loafs, naps long, moves slowly.
  case sleepyhead
  /// Playful and energetic: zoomies, pounces, bats at anything, quick on its feet.
  case clown

  public var title: String {
    switch self {
    case .cuddler: "Cuddler"
    case .explorer: "Explorer"
    case .diva: "Diva"
    case .sleepyhead: "Sleepyhead"
    case .clown: "Clown"
    }
  }

  /// One short line for choosing a cat.
  public var line: String {
    switch self {
    case .cuddler: "Always on your lap, purring at a look."
    case .explorer: "Into every box and up every shelf."
    case .diva: "Affection on its own terms, and the best cushion."
    case .sleepyhead: "Naps first, asks questions later."
    case .clown: "Zoomies at dawn, a game out of anything."
    }
  }

  /// The traits at the heart of the type.
  public var archetype: CatPersonality {
    switch self {
    case .cuddler:
      CatPersonality(curious: 0.45, lazy: 0.55, cuddly: 0.9, playful: 0.45, bold: 0.4, vocal: 0.7)
    case .explorer:
      CatPersonality(curious: 0.9, lazy: 0.3, cuddly: 0.4, playful: 0.6, bold: 0.85, vocal: 0.45)
    case .diva:
      CatPersonality(curious: 0.5, lazy: 0.55, cuddly: 0.2, playful: 0.35, bold: 0.75, vocal: 0.85)
    case .sleepyhead:
      CatPersonality(curious: 0.3, lazy: 0.9, cuddly: 0.6, playful: 0.2, bold: 0.3, vocal: 0.2)
    case .clown:
      CatPersonality(curious: 0.65, lazy: 0.1, cuddly: 0.55, playful: 0.9, bold: 0.65, vocal: 0.6)
    }
  }

  /// The type `personality` leans towards most, measured from an even cat along the way each
  /// type's heart lies. A cat adopted before temperaments existed gets the one that fits the
  /// traits it already had. Leaning, rather than nearness, keeps the types about equally common:
  /// the Cuddler's heart lies nearest an even cat and would take nearly half of them.
  public static func fitting(_ personality: CatPersonality) -> CatTemperament {
    func lean(_ type: CatTemperament) -> Double {
      var along = 0.0
      var length = 0.0
      for trait in CatPersonality.Trait.allCases {
        let way = type.archetype[trait] - 0.5
        along += (personality[trait] - 0.5) * way
        length += way * way
      }
      return along / length.squareRoot()
    }
    // Ties fall to the earlier type, so every phone picks the same.
    return allCases.max { lean($0) < lean($1) } ?? .cuddler
  }

  /// The type a pet with this seed is born with: the one that fits its seeded traits.
  public static func born(seed: UInt64) -> CatTemperament {
    fitting(.seeded(seed))
  }

  /// How much of the nature is the type's: the rest is the seed's own, so two Clowns are still
  /// two cats.
  public static let pull = 0.65

  /// The nature of a cat of this type with `seeded` traits: pulled most of the way to the type.
  public func nature(from seeded: CatPersonality) -> CatPersonality {
    var nature = seeded
    for trait in CatPersonality.Trait.allCases {
      nature[trait] = seeded[trait] + (archetype[trait] - seeded[trait]) * Self.pull
    }
    return nature
  }

  /// How fast its clips play and it moves, against an even cat's 1.
  public var tempo: Double {
    switch self {
    case .cuddler: 1
    case .explorer: 1.1
    case .diva: 0.92
    case .sleepyhead: 0.78
    case .clown: 1.22
    }
  }

  /// How big its small movements are, blinks, flicks and breath, against an even cat's 1.
  public var amplitude: Double {
    switch self {
    case .cuddler: 1
    case .explorer: 1.1
    case .diva: 0.85
    case .sleepyhead: 0.7
    case .clown: 1.3
    }
  }

  /// How far it keeps from a finger, from 0 (comes right up) to 1 (stays well back).
  public var personalSpace: Double {
    switch self {
    case .cuddler: 0.05
    case .explorer: 0.35
    case .diva: 0.7
    case .sleepyhead: 0.3
    case .clown: 0.15
    }
  }

  /// How much more or less often each activity comes up than for an even cat. Strong on purpose:
  /// a Clown is at play and a Sleepyhead loafing within half a minute.
  public func bias(_ group: CatActivityGroup) -> Double {
    biases[group] ?? 1
  }

  private var biases: [CatActivityGroup: Double] {
    switch self {
    case .cuddler: [.social: 2.6, .idle: 1.2, .mischief: 0.5]
    case .explorer: [.explore: 2.6, .watch: 1.5, .idle: 0.6]
    case .diva: [.groom: 2.4, .watch: 1.4, .social: 0.5, .mischief: 1.6]
    case .sleepyhead: [.rest: 2.4, .idle: 1.6, .play: 0.45, .explore: 0.45]
    case .clown: [.play: 2.8, .mischief: 2, .idle: 0.55, .rest: 0.55]
    }
  }

  /// How strongly each need shows in what it does: a Cuddler minds being loved most, a Clown
  /// playing, a Sleepyhead its rest, a Diva its meals.
  public func weight(_ need: PetNeed) -> Double {
    needWeights[need] ?? 1
  }

  private var needWeights: [PetNeed: Double] {
    switch self {
    case .cuddler: [.loved: 1.6]
    case .explorer: [.playful: 1.25]
    case .diva: [.full: 1.4, .loved: 0.75]
    case .sleepyhead: [.rested: 1.6, .playful: 0.7]
    case .clown: [.playful: 1.6]
    }
  }

  /// What it does once a touch from either of you ends: a Cuddler comes for more, a Clown is off
  /// on a dash, a Diva tidies its fur, an Explorer looks about, a Sleepyhead goes on as it was.
  public var afterTouch: [CatActivityStep]? {
    switch self {
    case .cuddler: [.seekYou, .rub]
    case .explorer: [.lookAround, .sit]
    case .diva: [.groomPaw]
    case .sleepyhead: nil
    case .clown: [.zoomies]
    }
  }
}
