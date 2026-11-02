import Foundation

/// Every constant of the pet's life, in one place, so it can be tuned remotely or split for an A/B
/// test. Times are in hours, values are fractions of a full need.
///
/// It decodes from a flat JSON object of numbers, and any key left out keeps its standard value,
/// so a remote override names only what it changes. The owner's tuning page uses the same keys.
public struct LifeConfig: Hashable, Sendable {
  /// No need ever falls below this.
  public var floor = 0.2
  /// Where every need starts, before any event.
  public var initial = 0.7

  /// How long each need takes to fall by 1/e of the way to the floor.
  public var fullHours = 10.0
  public var lovedHours = 24.0
  public var playfulHours = 8.0
  /// Rested falls while awake and rises while asleep.
  public var restedAwakeHours = 18.0
  public var restedAsleepHours = 2.5
  /// How fast Full and Playful fall while asleep, as a share of their awake pace.
  public var fullAsleepPace = 0.5
  public var playfulAsleepPace = 0.3

  /// The exponent k of the diminishing return `n ← n + g·(1 − n)^k`.
  public var returns = 1.5
  public var feedGain = 0.5
  public var petGain = 0.18
  public var playGain = 0.35
  /// A note fills Loved for both partners, more than anything else.
  public var noteGain = 0.4
  /// A game also counts a little as care from whoever played.
  public var playLoveGain = 0.06
  /// What a game costs in Rested.
  public var playTiring = 0.05

  /// The hour of the night when sleepiness peaks, in the pair's local time.
  public var sleepiestHour = 3.0
  /// Sleep pressure is `rhythm·s(h) + tiredness·(1 − Rested)`.
  public var rhythmWeight = 0.6
  public var tirednessWeight = 0.6
  /// It falls asleep when the pressure rises above this, and wakes when it drops below `wakeBelow`.
  public var sleepAbove = 0.7
  public var wakeBelow = 0.5
  /// After something wakes it, how long it stays up before it can doze off again.
  public var stayUpHours = 0.33

  /// How hard the softer of the two partners' Loved pulls the shared one down. Higher is closer
  /// to a plain minimum.
  public var loveSharpness = 10.0
  /// A partner whose Loved is this far below the other's is missed.
  public var missingGap = 0.25

  /// Mood is `Π nᵢ^wᵢ` with these weights. Loved weighs most.
  public var fullWeight = 0.2
  public var restedWeight = 0.2
  public var lovedWeight = 0.4
  public var playfulWeight = 0.2

  /// A need counts as low below `lowBelow`, and stops counting once it is back above `lowUntil`.
  public var lowBelow = 0.35
  public var lowUntil = 0.5
  /// The temperature of the softmax over urgency `(1 − n)²`.
  public var temperature = 0.08

  /// The longest step the fold takes without an event, in hours, and how far back it looks.
  public var stepHours = 0.25
  public var horizonHours = 168.0

  public init() {}

  public static let standard = LifeConfig()

  public var weights: PetNeeds {
    PetNeeds(full: fullWeight, rested: restedWeight, loved: lovedWeight, playful: playfulWeight)
  }

  /// Every constant by its JSON key, the one list that encoding, decoding and the tuning page share.
  public static let keys: [(name: String, path: WritableKeyPath<LifeConfig, Double> & Sendable)] = [
    ("floor", \.floor), ("initial", \.initial),
    ("fullHours", \.fullHours), ("lovedHours", \.lovedHours), ("playfulHours", \.playfulHours),
    ("restedAwakeHours", \.restedAwakeHours), ("restedAsleepHours", \.restedAsleepHours),
    ("fullAsleepPace", \.fullAsleepPace), ("playfulAsleepPace", \.playfulAsleepPace),
    ("returns", \.returns), ("feedGain", \.feedGain), ("petGain", \.petGain),
    ("playGain", \.playGain), ("noteGain", \.noteGain), ("playLoveGain", \.playLoveGain),
    ("playTiring", \.playTiring), ("sleepiestHour", \.sleepiestHour),
    ("rhythmWeight", \.rhythmWeight), ("tirednessWeight", \.tirednessWeight),
    ("sleepAbove", \.sleepAbove), ("wakeBelow", \.wakeBelow), ("stayUpHours", \.stayUpHours),
    ("loveSharpness", \.loveSharpness), ("missingGap", \.missingGap),
    ("fullWeight", \.fullWeight), ("restedWeight", \.restedWeight),
    ("lovedWeight", \.lovedWeight), ("playfulWeight", \.playfulWeight),
    ("lowBelow", \.lowBelow), ("lowUntil", \.lowUntil), ("temperature", \.temperature),
    ("stepHours", \.stepHours), ("horizonHours", \.horizonHours),
  ]
}

extension LifeConfig: Codable {
  private struct Key: CodingKey {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    self.init()
    for (name, path) in Self.keys {
      if let value = try container.decodeIfPresent(Double.self, forKey: Key(stringValue: name)),
        value.isFinite
      {
        self[keyPath: path] = value
      }
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    for (name, path) in Self.keys {
      try container.encode(self[keyPath: path], forKey: Key(stringValue: name))
    }
  }
}
