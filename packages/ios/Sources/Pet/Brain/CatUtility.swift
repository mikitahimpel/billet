import Foundation

/// One group's score, kept with its factors so the debug overlay can say why.
public struct CatUtilityScore: Hashable, Sendable {
  public var group: CatActivityGroup
  public var score: Double
  public var need: Double
  public var personality: Double
  /// The temperament's lean towards the group, 1 for a cat with none.
  public var temperament: Double
  public var time: Double
  public var room: Double
  public var novelty: Double
  public var mood: Double
  public var vitality: Double
}

/// A group the cat played recently, for the boredom penalty.
public struct CatEpisode: Hashable, Sendable {
  public var group: CatActivityGroup
  public var start: Double
  public var end: Double
}

/// Everything the utility reads, at one moment.
public struct CatUtilityInput: Sendable {
  public var now: Double
  public var needs: PetNeeds
  public var focus: PetNeed?
  public var mood: Double
  /// The pair's local hour, 0 up to 24.
  public var hour: Double
  public var vitality: CatVitality
  /// Whether the sleep pressure is high, rather than the cat only being drowsy from a nap.
  public var sleepy: Bool
  public var personality: CatPersonality
  public var temperament: CatTemperament?
  public var room: RoomAffordances
  public var weather: ViewWeather
  public var recent: [CatEpisode]
  /// How long the partner seen least recently has been away, in hours.
  public var awayHours: Double
  /// Whether any reachable piece is still uninspected.
  public var hasNovelty: Bool
  /// How much the cat likes its best spots, from its memory: 0 for none, up to 1.
  public var spotFondness: Double
}

/// Scores each activity group: `need × personality × time of day × room × novelty × mood ×
/// vitality`, then chooses by softmax with a temperature. Pure: the same input gives the same
/// scores on every phone.
public enum CatUtility {
  /// The softmax temperature over log scores: lower picks the best more surely.
  public static let temperature = 0.35
  /// A group in play keeps the cat unless another scores this many times better.
  public static let hysteresis = 1.6
  /// How long a recent group keeps putting the cat off playing it again, in seconds.
  public static let boredomSeconds = 240.0

  public static func scores(_ input: CatUtilityInput) -> [CatUtilityScore] {
    CatActivityGroup.chosen.map { score($0, input) }
  }

  static func score(_ group: CatActivityGroup, _ input: CatUtilityInput) -> CatUtilityScore {
    let need = needTerm(group, input)
    let traits = personalityTerm(group, input.personality)
    let kind = input.temperament?.bias(group) ?? 1
    let time = timeTerm(group, hour: input.hour)
    let room = roomTerm(group, input)
    let novelty = noveltyTerm(group, input)
    let mood = moodTerm(group, mood: input.mood)
    let vitality = vitalityTerm(group, input.vitality, sleepy: input.sleepy)
    return CatUtilityScore(
      group: group,
      score: base(group) * need * traits * kind * time * room * novelty * mood * vitality,
      need: need, personality: traits, temperament: kind, time: time, room: room,
      novelty: novelty, mood: mood,
      vitality: vitality)
  }

  static func base(_ group: CatActivityGroup) -> Double {
    switch group {
    case .idle: 1
    case .explore: 0.7
    case .rest: 0.55
    case .groom: 0.6
    case .eat: 0.3
    case .play: 0.6
    case .watch: 0.7
    case .social: 0.55
    case .mischief: 0.12
    case .react: 0
    }
  }

  /// `0.5 + 4·(1 − n)²` for the need a group answers, half again if it is the need in focus.
  /// Rest starts lower: a rested cat naps now and then, a tired one curls up.
  static func needTerm(_ group: CatActivityGroup, _ input: CatUtilityInput) -> Double {
    let need: PetNeed? =
      switch group {
      case .rest: .rested
      case .eat: .full
      case .play, .mischief: .playful
      case .social: .loved
      case .idle, .explore, .groom, .watch, .react: nil
      }
    guard let need else { return 1 }
    let weight = input.temperament?.weight(need) ?? 1
    let term = (need == .rested ? 0.25 : 0.5) + 4 * weight * NeedFocus.urgency(input.needs[need])
    return input.focus == need ? term * 1.5 : term
  }

  static func personalityTerm(_ group: CatActivityGroup, _ p: CatPersonality) -> Double {
    switch group {
    case .idle: p.lean([(.lazy, 0.3), (.curious, -0.2)])
    case .explore: p.lean([(.curious, 0.8), (.bold, 0.3), (.lazy, -0.3)])
    case .rest: p.lean([(.lazy, 0.7), (.playful, -0.2)])
    case .groom: p.lean([(.lazy, 0.2)])
    case .eat: 1
    case .play: p.lean([(.playful, 0.8), (.lazy, -0.4), (.bold, 0.2)])
    case .watch: p.lean([(.curious, 0.4), (.lazy, 0.2)])
    case .social: p.lean([(.cuddly, 0.8), (.vocal, 0.4)])
    case .mischief: p.lean([(.bold, 0.8), (.playful, 0.4), (.curious, 0.3)])
    case .react: 1
    }
  }

  /// Cats are busiest at dawn and dusk and nap through the middle of the day.
  static func timeTerm(_ group: CatActivityGroup, hour: Double) -> Double {
    func near(_ peak: Double, width: Double) -> Double {
      var gap = abs(hour - peak).truncatingRemainder(dividingBy: 24)
      if gap > 12 { gap = 24 - gap }
      return exp(-(gap * gap) / (2 * width * width))
    }
    let twilight = max(near(6.5, width: 1.5), near(19, width: 1.8))
    let midday = near(13.5, width: 2)
    let daylight = hour >= 8 && hour < 18 ? 1.0 : 0.0
    switch group {
    case .play, .mischief: return 1 + 0.7 * twilight - 0.2 * midday
    case .explore: return 1 + 0.4 * twilight
    case .rest: return 1 + 0.6 * midday
    case .watch: return 1 + 0.3 * daylight + 0.3 * twilight
    case .idle, .groom, .eat, .social, .react: return 1
    }
  }

  static func roomTerm(_ group: CatActivityGroup, _ input: CatUtilityInput) -> Double {
    let room = input.room
    switch group {
    case .watch:
      guard room.has(.window) else { return 0 }
      let weather: Double =
        switch input.weather {
        case .rain, .snow: 1.6
        case .fog: 1.1
        case .clear: 1
        }
      return weather * (input.awayHours > CatBrainConfig.missingAfterHours ? 1.3 : 1)
    case .mischief:
      let options = [room.reachable(.smallItem), room.reachable(.soft), room.reachable(.desk)]
      return Double(options.filter(\.self).count) / 2
    case .eat: return room.reachable(.bowl) ? 1 : 0.2
    case .rest:
      let sunny = room.has(.sunbeam) ? 1.25 : 1
      let soft = room.reachable(.bed) || room.reachable(.soft) ? 1.15 : 1
      return sunny * soft * (1 + 0.3 * input.spotFondness)
    case .explore: return input.hasNovelty ? 2.2 : 1
    case .play: return room.reachable(.toy) ? 1.15 : 1
    case .social: return input.awayHours > CatBrainConfig.missingAfterHours ? 1.3 : 1
    case .idle, .groom, .react: return 1
    }
  }

  /// `Π (1 − 0.6·e^(−age/240 s))` over the recent episodes of the group, so a cat that just
  /// groomed is less keen to groom again, and the idle groups wear off quickest.
  static func noveltyTerm(_ group: CatActivityGroup, _ input: CatUtilityInput) -> Double {
    var term = 1.0
    for episode in input.recent where episode.group == group {
      let age = max(input.now - episode.end, 0)
      term *= 1 - 0.6 * exp(-age / boredomSeconds)
    }
    return max(term, 0.05)
  }

  /// A happy cat plays and seeks company more. A low one rests more and still seeks company:
  /// it never sulks.
  static func moodTerm(_ group: CatActivityGroup, mood: Double) -> Double {
    switch group {
    case .play, .mischief, .explore: 0.6 + 0.6 * mood
    case .rest: 1.2 - 0.3 * mood
    case .social: 0.9 + 0.2 * mood
    case .idle, .groom, .eat, .watch, .react: 1
    }
  }

  /// A sleepy cat turns to rest; one still drowsy from a nap only slows down for a moment.
  static func vitalityTerm(_ group: CatActivityGroup, _ vitality: CatVitality, sleepy: Bool)
    -> Double
  {
    switch (vitality, group) {
    case (.awake, _): 1
    case (.drowsy, .rest): sleepy ? 3 : 0.6
    case (.drowsy, .groom), (.drowsy, .idle): 1
    case (.drowsy, .watch): 0.8
    case (.drowsy, _): sleepy ? 0.2 : 0.7
    case (.asleep, .rest): 1
    case (.asleep, _): 0
    }
  }

  /// The softmax `sᵢ^(1/T) / Σ sⱼ^(1/T)` over the scores, in their order.
  public static func probabilities(_ scores: [CatUtilityScore]) -> [Double] {
    let logs = scores.map { $0.score > 0 ? log($0.score) / temperature : -Double.infinity }
    guard let top = logs.max(), top.isFinite else {
      return scores.map { _ in 1 / Double(max(scores.count, 1)) }
    }
    let weights = logs.map { exp($0 - top) }
    let total = weights.reduce(0, +)
    return weights.map { $0 / total }
  }

  /// The group drawn by `roll`, from 0 up to 1, among `scores`.
  public static func choose(_ scores: [CatUtilityScore], roll: Double) -> CatActivityGroup {
    var left = roll
    let odds = probabilities(scores)
    for (score, p) in zip(scores, odds) {
      left -= p
      if left < 0 { return score.group }
    }
    return scores.last { $0.score > 0 }?.group ?? .idle
  }
}
