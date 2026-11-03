import Foundation

/// A toy in the room.
public enum CatToy: String, CaseIterable, Hashable, Sendable {
  /// A feather on a string, dragged along the cat's floor.
  case wand
  /// A pointer whose red dot follows the finger across the floor.
  case laser
  /// A light ball, flicked to roll. The cat chases it and sometimes brings it back.
  case ball
  /// A ball of yarn, flicked like the ball but slower and never brought back.
  case yarn

  /// Whether a flick sends it rolling, rather than the finger carrying it.
  public var isThrown: Bool {
    switch self {
    case .ball, .yarn: true
    case .wand, .laser: false
    }
  }
}

/// A trick the cat does when its own name is called twice, as a double tap on it.
public enum CatTrick: String, CaseIterable, Hashable, Sendable {
  case sit
  case wave
  case spin
  /// A paw raised to meet your finger. Only a cat that has learned it does it.
  case highFive
}

/// What a person did to the cat or near it, as the room tells the play machine.
public enum CatPlayEvent: Hashable, Sendable {
  /// A finger is stroking `zone`. Rooms send it when a stroke starts and when its zone or
  /// direction changes, not on every move.
  case stroke(PetZone, StrokeDirection)
  /// A toy started moving near the cat.
  case toyMoved(CatToy)
  /// The cat got to a toy it was after.
  case toyCaught(CatToy)
  case bowlFilled
  /// A treat is held out near the cat's nose.
  case treatHeldOut
  case lifted
  case placed
  /// A double tap on the floor, calling the cat there.
  case called
  /// A double tap on the cat.
  case trickAsked
  /// The partner petted the cat on their phone.
  case partnerPetted
  /// The partner gave the day's treat on their phone.
  case partnerTreated
}

/// How the cat answers, for the room to play with the cat's own clips.
public enum CatPlayReaction: Hashable, Sendable {
  /// Leans into the hand and purrs; eyes close when it is the head or chin.
  case lean(eyesClosed: Bool)
  /// Rubbed the wrong way: a flick of the tail, and it leans away.
  case flick
  /// On its back, it hugs the hand and kicks.
  case grab
  /// Watches the toy, stalks, wiggles and pounces.
  case stalk(CatToy)
  /// Only its head follows the toy: it has played enough for now.
  case watch(CatToy)
  /// Runs after a thrown toy; with `fetch` it carries it back towards the camera.
  case chase(CatToy, fetch: Bool)
  /// Pounced and caught it: a happy beat.
  case caught(CatToy)
  /// Trots to the bowl and eats.
  case eat
  /// Sniffs at the treat and takes it.
  case takeTreat
  /// Sniffs and turns away: it is full.
  case refuse
  case dangle
  case settle
  /// Walks to where it was called.
  case come
  /// Looks over and blinks slowly, but stays.
  case ignore
  case trick(CatTrick)
  /// Something from the partner: it perks up and looks around for them.
  case partnerLove
}

/// A haptic the room plays with a reaction. The app makes no sound; haptics and motion carry it.
public enum CatHaptic: Hashable, Sendable {
  /// A purr under the finger, from 0 to 1.
  case purr(strength: Double)
  /// A soft double tap: rubbed the wrong way, or a slow blink from across the room.
  case nudge
  case grab
  case pounce
  /// Little crunches while it eats.
  case chomp
  case lift
  case settle
  case trick
}

/// Care the cat's life counts, as a room reports it upward. Pets are reported where a stroke
/// starts, so the machine only counts what a stroke cannot.
public enum CatCare: Hashable, Sendable {
  case feed
  /// One game: counted at most once a ``CatPlay/gameGap``.
  case play
}

/// What the room does in answer to one event.
public struct CatPlayResponse: Hashable, Sendable {
  public var reaction: CatPlayReaction
  public var haptic: CatHaptic?
  /// What the cat's life counts this time, if anything.
  public var need: CatCare?
  /// How keen the cat is, from 0 to 1, for rooms that scale motion by it.
  public var interest: Double

  public init(
    reaction: CatPlayReaction, haptic: CatHaptic? = nil, need: CatCare? = nil,
    interest: Double = 1
  ) {
    self.reaction = reaction
    self.haptic = haptic
    self.need = need
    self.interest = interest
  }
}

/// Decides how the cat answers each thing done to it, so that the same touch again and again
/// gets a smaller answer and nothing ever feels like a button. Each kind of play has its own
/// tiredness, which grows with use and fades with time, and its own cooldown before the big
/// reaction can come again. Needs are counted at most once a while per kind.
///
/// Pure and deterministic for a given seed: rooms pass the time, in seconds on any clock.
public struct CatPlay: Sendable {
  enum Kind: Hashable, Sendable {
    case petting, belly
    case toy(CatToy)
    case food, treat, lift, call, trick, partner
  }

  /// How each kind tires the cat: what one go adds, how fast it fades, and the cooldown.
  struct Tiring: Sendable {
    var cost: Double
    /// Seconds for the tiredness to halve.
    var halfLife: Double
    /// Seconds before the full reaction can come again; within it the small one plays.
    var cooldown: Double
  }

  static func tiring(_ kind: Kind) -> Tiring {
    switch kind {
    case .petting: Tiring(cost: 0.08, halfLife: 40, cooldown: 0)
    case .belly: Tiring(cost: 0.35, halfLife: 30, cooldown: 7)
    case .toy: Tiring(cost: 0.3, halfLife: 50, cooldown: 1.5)
    case .food: Tiring(cost: 2, halfLife: 600, cooldown: 20)
    case .treat: Tiring(cost: 0.4, halfLife: 120, cooldown: 4)
    case .lift: Tiring(cost: 0.3, halfLife: 40, cooldown: 0)
    case .call: Tiring(cost: 0.3, halfLife: 40, cooldown: 3)
    case .trick: Tiring(cost: 0.3, halfLife: 45, cooldown: 2.5)
    case .partner: Tiring(cost: 0, halfLife: 1, cooldown: 2)
    }
  }

  /// Below this keenness a toy, a call or a trick only gets a look.
  public static let keen = 0.4
  /// The bowl or a treat past this much tiredness is refused.
  static let full = 1.5
  /// The shortest time between two games counted as play, in seconds, as the rooms' own bats.
  public static let gameGap = 60.0
  /// The shortest time between two meals counted, in seconds.
  static let mealGap = 60.0

  static func needGap(_ need: CatCare) -> Double {
    switch need {
    case .play: gameGap
    case .feed: mealGap
    }
  }

  /// How likely a belly rub is to end in a grab, at no tiredness and at most.
  static let grabChance = 0.3...0.85
  /// How likely a caught ball is to be brought back, at full keenness.
  static let fetchChance = 0.45

  private var tired: [Kind: (level: Double, at: Double)] = [:]
  private var lastFull: [Kind: Double] = [:]
  private var lastNeed: [CatCare: Double] = [:]
  private var nextTrick = 0
  /// The tricks care has taught the cat: it comes whenever called, and gives a high-five.
  public var learned: Set<CatLearnedTrick> = []
  private var random: SplitMix64

  public init(seed: UInt64 = 1) { random = SplitMix64(seed: seed) }

  /// How keen the cat is on `kind` at `now`, from 1 (fresh) towards 0.
  func interest(_ kind: Kind, at now: Double) -> Double {
    1 / (1 + tiredness(kind, at: now))
  }

  func tiredness(_ kind: Kind, at now: Double) -> Double {
    guard let entry = tired[kind] else { return 0 }
    let fading = Self.tiring(kind).halfLife
    return entry.level * pow(0.5, max(now - entry.at, 0) / fading)
  }

  /// Keenness on a toy, for rooms deciding whether to start a game on their own.
  public func interest(in toy: CatToy, at now: Double) -> Double {
    interest(.toy(toy), at: now)
  }

  private mutating func use(_ kind: Kind, at now: Double, times: Double = 1) {
    tired[kind] = (tiredness(kind, at: now) + Self.tiring(kind).cost * times, now)
  }

  private func isCooling(_ kind: Kind, at now: Double) -> Bool {
    guard let last = lastFull[kind] else { return false }
    return now - last < Self.tiring(kind).cooldown
  }

  private mutating func need(_ need: CatCare, at now: Double) -> CatCare? {
    if let last = lastNeed[need], now - last < Self.needGap(need) { return nil }
    lastNeed[need] = now
    return need
  }

  /// The cat's answer to `event` at `now`, or nil when it lets it pass without a reaction.
  public mutating func handle(_ event: CatPlayEvent, at now: Double) -> CatPlayResponse? {
    switch event {
    case .stroke(let zone, let direction):
      return stroke(zone, direction, at: now)
    case .toyMoved(let toy):
      let kind = Kind.toy(toy)
      let keenness = interest(kind, at: now)
      if isCooling(kind, at: now) { return nil }
      lastFull[kind] = now
      if keenness < Self.keen {
        return CatPlayResponse(reaction: .watch(toy), interest: keenness)
      }
      use(kind, at: now)
      let reaction: CatPlayReaction =
        toy.isThrown
        ? .chase(toy, fetch: toy == .ball && random.next(in: 0...1) < Self.fetchChance * keenness)
        : .stalk(toy)
      return CatPlayResponse(reaction: reaction, interest: keenness)
    case .toyCaught(let toy):
      return CatPlayResponse(
        reaction: .caught(toy), haptic: .pounce, need: need(.play, at: now),
        interest: interest(.toy(toy), at: now))
    case .bowlFilled:
      let tiredness = tiredness(.food, at: now)
      if isCooling(.food, at: now) || tiredness >= Self.full {
        return CatPlayResponse(reaction: .refuse, haptic: .nudge, interest: 1 / (1 + tiredness))
      }
      lastFull[.food] = now
      use(.food, at: now)
      return CatPlayResponse(
        reaction: .eat, haptic: .chomp, need: need(.feed, at: now), interest: 1 / (1 + tiredness))
    case .treatHeldOut:
      let tiredness = tiredness(.treat, at: now)
      if isCooling(.treat, at: now) { return nil }
      lastFull[.treat] = now
      if tiredness >= Self.full {
        return CatPlayResponse(reaction: .refuse, haptic: .nudge, interest: 1 / (1 + tiredness))
      }
      use(.treat, at: now)
      return CatPlayResponse(
        reaction: .takeTreat, haptic: .chomp, need: need(.feed, at: now),
        interest: 1 / (1 + tiredness))
    case .lifted:
      use(.lift, at: now)
      return CatPlayResponse(reaction: .dangle, haptic: .lift, interest: interest(.lift, at: now))
    case .placed:
      return CatPlayResponse(reaction: .settle, haptic: .settle)
    case .called:
      if isCooling(.call, at: now) { return nil }
      lastFull[.call] = now
      let keenness = interest(.call, at: now)
      if keenness < Self.keen, !learned.contains(.comesWhenCalled) {
        return CatPlayResponse(reaction: .ignore, haptic: .nudge, interest: keenness)
      }
      use(.call, at: now)
      return CatPlayResponse(reaction: .come, interest: keenness)
    case .trickAsked:
      if isCooling(.trick, at: now) { return nil }
      lastFull[.trick] = now
      let keenness = interest(.trick, at: now)
      if keenness < Self.keen {
        return CatPlayResponse(reaction: .ignore, haptic: .nudge, interest: keenness)
      }
      use(.trick, at: now)
      // A cat that knows the high-five gives it every other time.
      let known = CatTrick.allCases.filter { $0 != .highFive }
      let trick =
        learned.contains(.highFive) && nextTrick % 2 == 1
        ? CatTrick.highFive : known[(nextTrick / 2) % known.count]
      nextTrick += 1
      return CatPlayResponse(
        reaction: .trick(trick), haptic: .trick, need: need(.play, at: now), interest: keenness)
    case .partnerPetted, .partnerTreated:
      // The partner's phone counts their care; this one only shows it.
      if isCooling(.partner, at: now) { return nil }
      lastFull[.partner] = now
      return CatPlayResponse(reaction: .partnerLove, haptic: .nudge)
    }
  }

  private mutating func stroke(
    _ zone: PetZone, _ direction: StrokeDirection, at now: Double
  ) -> CatPlayResponse? {
    use(.petting, at: now)
    let comfort = interest(.petting, at: now)
    let pet: CatCare? = nil
    switch (zone, direction) {
    case (.belly, _):
      let overdone = min(tiredness(.belly, at: now), 1)
      use(.belly, at: now)
      let chance =
        Self.grabChance.lowerBound
        + (Self.grabChance.upperBound - Self.grabChance.lowerBound) * overdone
      if !isCooling(.belly, at: now), random.next(in: 0...1) < chance {
        lastFull[.belly] = now
        return CatPlayResponse(reaction: .grab, haptic: .grab, need: pet, interest: comfort)
      }
      return CatPlayResponse(
        reaction: .lean(eyesClosed: true), haptic: .purr(strength: 0.5), need: pet,
        interest: comfort)
    case (.back, .againstFur):
      return CatPlayResponse(reaction: .flick, haptic: .nudge, need: pet, interest: comfort)
    case (.head, _), (.chin, _):
      return CatPlayResponse(
        reaction: .lean(eyesClosed: true),
        haptic: .purr(strength: zone == .chin ? 0.75 : 0.6), need: pet, interest: comfort)
    case (.back, .withFur), (.back, .across):
      return CatPlayResponse(
        reaction: .lean(eyesClosed: false), haptic: .purr(strength: 0.45), need: pet,
        interest: comfort)
    }
  }
}
