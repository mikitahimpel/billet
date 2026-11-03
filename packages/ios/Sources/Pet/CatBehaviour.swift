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
    case .idle, .walk, .sit, .sleep, .crouchWiggle, .pounce, .eat, .blink, .look, .tailFlick,
      .happy, .stretch, .yawn, .groom, .knead, .slowBlink, .perk, .twitch:
      []
    }
  }
}

/// The pose a clip starts and ends in.
public enum CatBase: String, Codable, Hashable, Sendable {
  case stand
  case sit
  case sleep
  /// Lying with the belly down and the paws tucked under.
  case loaf
}

/// What one model's clip is like, read from its clip table.
public struct CatClipInfo: Hashable, Sendable {
  public var duration: Double
  public var loops: Bool
  public var base: CatBase
  /// The pose the clip ends in: its base, except for a clip that goes from one base to another.
  public var ends: CatBase

  public init(duration: Double, loops: Bool, base: CatBase, ends: CatBase? = nil) {
    self.duration = duration
    self.loops = loops
    self.base = base
    self.ends = ends ?? base
  }
}

/// Something the people did to the cat.
public enum CatReaction: Hashable, Sendable {
  /// A stroke on the head or back: eyes close and it purrs.
  case pet
  /// A tap: ears perk and the head tilts.
  case tap
  /// A treat: it eats, then is pleased.
  case treat
  /// A long pet: it rolls onto its back.
  case roll
  /// A finger at the edge of the screen: it bats at it.
  case bat
}

/// What the room should show now.
public struct CatBeat: Hashable, Sendable {
  public var action: CatAction
  /// How much the head may turn to look at the viewer, from 0 to 1.
  public var lookWeight: Double

  public init(action: CatAction, lookWeight: Double) {
    self.action = action
    self.lookWeight = lookWeight
  }
}

/// Chooses the cat's clips over time so it seems to live on its own: it naps, wakes for a while,
/// yawns, grooms, looks at you, kneads and settles again. Weighted picks with cooldowns keep it
/// from repeating, and reactions to touch cut in. Pure and deterministic for a given seed; the
/// room calls `beat(at:mode:)` each frame, which costs a few comparisons unless the beat changes.
public struct CatBehaviour: Sendable {
  /// How much say the room gives the cat.
  public enum Mode: Hashable, Sendable {
    /// Nothing is going on: it naps and wakes on its own.
    case free
    /// The room wants it awake (a note is arriving or it is settling): idles, never sleeps.
    case awake
    /// The room has decided (walking, playing): the cue is exactly this.
    case fixed(CatAction)
  }

  struct Pick {
    let action: CatAction
    let weight: Double
    let cooldown: Double
  }

  /// The awake repertoire. Weights are relative; cooldowns are seconds before it can come again.
  static let repertoire: [Pick] = [
    Pick(action: .slowBlink, weight: 3, cooldown: 14),
    Pick(action: .look, weight: 3, cooldown: 10),
    Pick(action: .groom, weight: 3, cooldown: 24),
    Pick(action: .blink, weight: 2, cooldown: 6),
    Pick(action: .tailFlick, weight: 2, cooldown: 10),
    Pick(action: .yawn, weight: 2, cooldown: 30),
    Pick(action: .knead, weight: 2, cooldown: 28),
    Pick(action: .perk, weight: 1, cooldown: 18),
    Pick(action: .stretch, weight: 1.5, cooldown: 40),
    Pick(action: .crouchWiggle, weight: 1, cooldown: 20),
  ]

  /// How much more often a move comes while the pet's life is focused on `need`. The crouch before
  /// a pounce only comes when it wants to play.
  static func boost(_ action: CatAction, for need: PetNeed?) -> Double {
    switch (need, action) {
    case (.rested, .yawn): 4
    case (.rested, .stretch): 2
    case (.rested, .perk): 0.3
    case (.playful, .perk): 3
    case (.playful, .tailFlick): 3
    case (.playful, .crouchWiggle): 2
    case (.full, .look): 3
    case (.full, .perk): 2
    case (.loved, .slowBlink): 3
    case (.loved, .knead): 2
    case (.loved, .look): 2
    case (_, .crouchWiggle): 0
    default: 1
    }
  }

  /// Seconds asleep before the first wake, so the first screen shows the cat stirring.
  static let firstNap = 3.0...5.0
  /// A nap, with a twitch every few seconds; a model that cannot twitch naps for less.
  static let nap = 10.0...16.0
  static let stillNap = 4.0...7.0
  /// Seconds of plain sleep between twitches.
  static let sleepBetweenTwitches = 4.0...7.0
  static let awakeSpell = 22.0...40.0
  /// Seconds between one-shots, resting in the sitting or standing loop.
  static let rest = 1.5...4.0
  /// How long a loop that stands in for a one-shot is held.
  static let heldLoop = 3.0...5.0
  static let petLength = 3.2
  static let treatEating = 4.0
  static let treatPleased = 2.4

  private let clips: [CatAction: CatClipInfo]
  private var random: SplitMix64
  private var current: CatAction?
  private var until = 0.0
  private var awakeUntil: Double?
  private var asleepUntil: Double?
  private var lastPlayed: [CatAction: Double] = [:]
  /// The last move picked from the repertoire, which the next pick avoids if it can.
  private var lastPick: CatAction?
  private var queue: [(CatAction, Double)] = []
  private var started = false
  private var drive = LifeDrive()

  public init(clips: [CatAction: CatClipInfo], seed: UInt64 = 1) {
    self.clips = clips
    random = SplitMix64(seed: seed)
  }

  /// Whether the cat is up at `now`, rather than asleep or about to fall asleep.
  public func isAwake(at now: Double) -> Bool {
    asleepUntil == nil && (awakeUntil.map { now < $0 } ?? false)
  }

  /// Whether this model has a clip for `action`.
  public func has(_ action: CatAction) -> Bool { clips[action] != nil }

  /// `action`, or the first stand-in this model has, or its resting loop.
  public func playable(_ action: CatAction) -> CatAction {
    ([action] + action.standIns).first(where: has) ?? resting
  }

  /// How long `action` lasts as this model plays it: a one-shot's length, or `held` for a loop.
  public func length(of action: CatAction, held: Double = 1.6) -> Double {
    clips[action].map { $0.loops ? held : $0.duration } ?? held
  }

  /// Cuts in with a reaction. It plays from the next `cue`, and the cat stays awake a while after.
  public mutating func react(_ reaction: CatReaction, at now: Double) {
    queue.removeAll()
    switch reaction {
    case .pet:
      queue.append((available(.happy) ?? resting, Self.petLength))
    case .tap:
      let perk = available(.perk) ?? available(.look) ?? resting
      queue.append((perk, clips[perk].map { $0.loops ? 1.6 : $0.duration } ?? 1.6))
    case .treat:
      if let eat = available(.eat) { queue.append((eat, Self.treatEating)) }
      queue.append((available(.happy) ?? resting, Self.treatPleased))
    case .roll:
      let roll = playable(.rollOver)
      queue.append((roll, length(of: roll, held: 3)))
    case .bat:
      let bat = playable(.bat)
      queue.append((bat, length(of: bat, held: 1.4)))
    }
    until = now
    asleepUntil = nil
    awakeUntil = max(awakeUntil ?? now, now + Self.awakeSpell.lowerBound)
  }

  /// Plays `action` next, or its nearest stand-in, for `seconds` (a one-shot's own length when
  /// nil), then goes on as before. For moves the room asks for that are not a ``CatReaction``.
  public mutating func perform(_ action: CatAction, for seconds: Double? = nil, at now: Double) {
    queue.removeAll()
    let shown = playable(action)
    queue.append((shown, seconds ?? length(of: shown)))
    until = now
    asleepUntil = nil
    awakeUntil = max(awakeUntil ?? now, now + Self.awakeSpell.lowerBound)
  }

  /// Follows the pet's life: asleep, it naps on in free mode and wakes only to touch; with a need
  /// in focus, the moves that show it come more often and its awake spells shorten when tired.
  public mutating func follow(_ drive: LifeDrive) {
    self.drive = drive
  }

  /// Plays a moment asked for from outside the room, such as an opening. Waking stretches (or
  /// yawns, or perks, as the model allows) and keeps the cat up a while. Looking at the viewer
  /// rests in the base loop, where the head is free to turn, once any waking move is done.
  public mutating func cue(_ cue: CatCue, at now: Double) {
    started = true
    switch cue {
    case .wakeUp:
      queue.removeAll()
      let waking = available(.stretch) ?? available(.yawn) ?? available(.perk) ?? resting
      queue.append((waking, clips[waking].map { $0.loops ? Self.heldWake : $0.duration } ?? 2))
      until = now
    case .lookAtCamera:
      let isWaking =
        queue.contains { Self.wakingMoves.contains($0.0) }
        || (current.map(Self.wakingMoves.contains) ?? false) && now < until
      if !isWaking {
        queue.removeAll()
        until = now
      }
      queue.append((resting, Self.viewerLook))
    }
    asleepUntil = nil
    awakeUntil = max(awakeUntil ?? now, now + Self.awakeSpell.lowerBound)
  }

  /// The moves a cue to wake may play, which a cue to look waits for.
  static let wakingMoves: Set<CatAction> = [.stretch, .yawn, .perk]
  /// How long a looping clip that stands in for waking is held.
  static let heldWake = 1.6
  /// How long the cat holds the viewer's eye when cued to.
  public static let viewerLook = 2.6

  /// The cue for `now`. Call it every frame; it only moves on when the current clip is done.
  public mutating func beat(at now: Double, mode: Mode) -> CatBeat {
    if case .fixed(let action) = mode {
      current = action
      until = now
      return CatBeat(action: action, lookWeight: Self.lookWeight(action))
    }
    if !started {
      started = true
      if mode == .free {
        asleepUntil = now + random.next(in: Self.firstNap)
      } else {
        awakeUntil = now + random.next(in: Self.awakeSpell)
      }
    }
    if now >= until || current == nil {
      advance(at: now, mode: mode)
    }
    let action = current ?? resting
    return CatBeat(action: action, lookWeight: Self.lookWeight(action))
  }

  private mutating func advance(at now: Double, mode: Mode) {
    if !queue.isEmpty {
      let (action, length) = queue.removeFirst()
      play(action, for: length, at: now)
      return
    }
    if mode == .free, drive.asleep, has(.sleep), awakeUntil.map({ now >= $0 }) ?? true {
      awakeUntil = nil
      asleepUntil = max(asleepUntil ?? now, now + Self.nap.lowerBound)
    }
    if mode == .free, let asleepUntil {
      if now < asleepUntil, has(.sleep) {
        dream(until: asleepUntil, at: now)
        return
      }
      self.asleepUntil = nil
      awakeUntil = now + random.next(in: Self.awakeSpell) * awakeShare
      if let waking = available(.yawn) ?? available(.stretch), let info = clips[waking], !info.loops
      {
        play(waking, for: info.duration, at: now)
        return
      }
    }
    if mode == .free, asleepUntil == nil, awakeUntil == nil {
      awakeUntil = now + random.next(in: Self.awakeSpell) * awakeShare
    }
    if mode == .free, let awakeUntil, now >= awakeUntil, has(.sleep) {
      self.awakeUntil = nil
      asleepUntil = now + random.next(in: has(.twitch) ? Self.nap : Self.stillNap)
      play(.sleep, for: random.next(in: Self.sleepBetweenTwitches), at: now)
      return
    }
    if mode == .awake, awakeUntil.map({ now >= $0 }) ?? true {
      awakeUntil = now + random.next(in: Self.awakeSpell)
    }
    // Alternate a one-shot with a rest in the base loop, so moves never run into each other.
    let wasResting =
      current == resting || current == .idle || current == .sleep || current == .twitch
      || current == nil
    if wasResting, let pick = choose(at: now) {
      let info = clips[pick]
      play(
        pick, for: info.map { $0.loops ? random.next(in: Self.heldLoop) : $0.duration } ?? 2,
        at: now)
    } else {
      play(restingLoop(), for: random.next(in: Self.rest), at: now)
    }
  }

  /// Asleep until `end`: plain sleep, broken by a twitch when there is room for one.
  private mutating func dream(until end: Double, at now: Double) {
    if current == .sleep, let twitch = clips[.twitch], end - now > twitch.duration + 1 {
      play(.twitch, for: twitch.duration, at: now)
    } else {
      play(.sleep, for: min(end - now, random.next(in: Self.sleepBetweenTwitches)), at: now)
    }
  }

  private mutating func play(_ action: CatAction, for length: Double, at now: Double) {
    current = action
    until = now + max(length, 0.2)
    lastPlayed[action] = now
  }

  /// A weighted pick among the moves this model has and that are off cooldown.
  private mutating func choose(at now: Double) -> CatAction? {
    let ready = Self.repertoire.filter { pick in
      guard has(pick.action), pick.action != current else { return false }
      guard let last = lastPlayed[pick.action] else { return true }
      return now - last >= pick.cooldown
    }
    let fresh = ready.filter { $0.action != lastPick }
    let open = (fresh.isEmpty ? ready : fresh).map {
      Pick(
        action: $0.action, weight: $0.weight * Self.boost($0.action, for: drive.focus),
        cooldown: $0.cooldown)
    }.filter { $0.weight > 0 }
    let total = open.reduce(0) { $0 + $1.weight }
    guard total > 0 else { return nil }
    var roll = random.next(in: 0...total)
    var chosen = open.last?.action
    for pick in open {
      roll -= pick.weight
      if roll <= 0 {
        chosen = pick.action
        break
      }
    }
    lastPick = chosen
    return chosen
  }

  /// Mostly sitting, now and then standing about.
  private mutating func restingLoop() -> CatAction {
    if has(.idle), !has(.sit) { return .idle }
    if has(.idle), random.next(in: 0...1) < 0.25 { return .idle }
    return resting
  }

  private var resting: CatAction { has(.sit) ? .sit : .idle }

  /// A tired pet stays up for less.
  private var awakeShare: Double { drive.focus == .rested ? 0.5 : 1 }

  private func available(_ action: CatAction) -> CatAction? { has(action) ? action : nil }

  /// How far the head turns this frame. While the room holds a look (a finger, the camera on
  /// cue) the head turns in any clip but sleep; Reduce Motion keeps it still.
  public static func lookWeight(for beat: CatBeat, holding: Bool, reduceMotion: Bool) -> Double {
    if reduceMotion { return 0 }
    guard holding, beat.action != .sleep else { return beat.lookWeight }
    return max(beat.lookWeight, heldLook)
  }

  static let heldLook = 0.85

  /// How freely the head may follow the viewer during `action`. Clips that move the head
  /// themselves, or keep it down, get little or none.
  public static func lookWeight(_ action: CatAction) -> Double {
    switch action {
    case .sit, .idle, .blink, .slowBlink, .tailFlick, .knead, .loaf: 1
    case .perk, .happy: 0.5
    case .walk, .eat, .run: 0.3
    case .bat, .wave: 0.6
    case .sniff: 0.4
    case .grab, .dangle: 0
    case .sleep, .twitch, .look, .groom, .yawn, .stretch, .crouchWiggle, .pounce, .rollOver,
      .headbutt, .reachUp, .lieDown:
      0
    }
  }
}

/// A small, fast, seedable generator, so a behaviour replays the same for the same seed.
public struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64

  public init(seed: UInt64) { state = seed }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func next(in range: ClosedRange<Double>) -> Double {
    Double.random(in: range, using: &self)
  }
}
