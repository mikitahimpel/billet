import Foundation

/// How the cat feels, worked out from its needs, whether it sleeps and its temperament. It is what
/// the needs card says and what the brain acts out: a hangry cat throws a tantrum, a lonely one
/// sulks, a bored one tears round the room. Pure, so both phones show the same mood.
public enum CatFeeling: String, CaseIterable, Codable, Hashable, Sendable {
  case asleep
  /// So hungry it throws a tantrum: yowls, knocks things off the seat, flops down in despair.
  case hangry
  /// Waits by the empty bowl, meows at you, paws at the bowl.
  case hungry
  /// Not petted for a while: sulks with its back to you and ignores the first touch.
  case lonely
  /// Not played with: zoomies, scratches the cushion, attacks the yarn, brings a toy.
  case bored
  /// Yawns, kneads and curls up.
  case sleepy
  /// Every need met: purrs, slow-blinks at you, rolls onto its back.
  case happy
  case content

  /// The mood in a word or two, with a face, for the needs card.
  public var words: String {
    switch self {
    case .asleep: "Fast asleep 💤"
    case .hangry: "Hangry 😾"
    case .hungry: "Peckish 🐟"
    case .lonely: "Sulking 😿"
    case .bored: "Restless 🧶"
    case .sleepy: "Sleepy 🥱"
    case .happy: "Happy 😻"
    case .content: "Content 😺"
    }
  }

  /// What it wants now, and how to give it, in a few words.
  public var wants: String {
    switch self {
    case .asleep: "To sleep. Let it dream"
    case .hangry: "Food, right now. Tap the bowl"
    case .hungry: "A meal. Tap the bowl"
    case .lonely: "A pet, maybe two"
    case .bored: "A game. Drag the yarn"
    case .sleepy: "A quiet nap"
    case .happy: "Nothing. Just you"
    case .content: "A little company"
    }
  }

  /// The need behind the feeling, for the thought bubble over the cat.
  public var need: PetNeed? {
    switch self {
    case .hangry, .hungry: .full
    case .lonely: .loved
    case .bored: .playful
    case .sleepy: .rested
    case .asleep, .happy, .content: nil
    }
  }

  /// Whether the feeling asks something of the pair, so care that ends it shows.
  public var isNeedy: Bool { need != nil && self != .sleepy }

  /// Mood at or above this, with no need low, is happy.
  public static let happyAbove = 0.68
  /// A hunger this strong, after the temperament's drama, is a tantrum.
  public static let tantrumAbove = 0.5

  /// How the cat feels with these needs. `sleepy` is whether the sleep pressure is high.
  public static func of(
    needs: PetNeeds, mood: Double, asleep: Bool, sleepy: Bool, temperament: CatTemperament?,
    config: LifeConfig = .standard
  ) -> CatFeeling {
    if asleep { return .asleep }
    let low = config.lowBelow
    let hunger = hunger(needs.full, temperament: temperament, config: config)
    if hunger >= tantrumAbove { return .hangry }
    if needs.full < low { return .hungry }
    if needs.loved < low { return .lonely }
    if needs.playful < low { return .bored }
    if sleepy || needs.rested < low { return .sleepy }
    if mood >= happyAbove { return .happy }
    return .content
  }

  /// How hungry the cat acts, from 0 (not hungry) up: how far Full is below the low line on its
  /// way to the floor, times its temperament's drama. A Diva throws a tantrum at a missed snack;
  /// a Sleepyhead barely notices until the bowl has been empty for half a day.
  public static func hunger(
    _ full: Double, temperament: CatTemperament?, config: LifeConfig = .standard
  ) -> Double {
    let span = max(config.lowBelow - config.floor, 1e-6)
    let below = min(max((config.lowBelow - full) / span, 0), 1)
    return below * (temperament?.drama ?? 1)
  }
}

extension CatTemperament {
  /// How big its feelings are, against an even cat's 1: a Diva overreacts, a Sleepyhead
  /// underreacts.
  public var drama: Double {
    switch self {
    case .cuddler: 1
    case .explorer: 0.9
    case .diva: 1.5
    case .sleepyhead: 0.55
    case .clown: 1.2
    }
  }
}

/// A sound the cat makes, for the scene to play and show.
public enum CatVoice: String, CaseIterable, Codable, Hashable, Sendable {
  /// A short ask, rising at the end.
  case meow
  /// A long, loud, falling complaint.
  case yowl
  /// A small trill, as when it drops a toy for you.
  case chirp
}
