import Foundation

/// What her attention asks of her body this instant. Goals, not eased values: whoever poses her
/// follows them with her own springs.
public struct CatRegard: Equatable, Sendable {
  /// Where the head points, radians from straight ahead of her body, within what the neck turns.
  public var headYaw = 0.0
  public var headPitch = 0.0
  /// A curious tilt of the head to one side.
  public var headRoll = 0.0
  /// Each ear's opening swung out and back toward a sound on its side (positive), or pricked
  /// forward onto what she watches (negative).
  public var earLeft = 0.0
  public var earRight = 0.0
  /// How much of the head's turn the chest takes up, once she has watched for a moment.
  public var chest = 0.0
  /// Radians she leans toward what interests her.
  public var lean = 0.0
  /// From 0, at ease, to 1, frozen: the rest of her holds still while she listens or stares.
  public var stillness = 0.0
  /// How quick the head is, from 0, drifting back to rest, to 1, a start.
  public var snap = 0.1
  /// How much the tail's tip twitches, the one part that gives away a cat staring.
  public var tailTip = 0.0
  /// From 0 to 1: eyes wide and blinks held back.
  public var alert = 0.0
  /// She blinks now: as she lets go of something, or at the start of a big turn of the head.
  public var blink = false
  /// What she attends to, if anything.
  public var source: CatStimulus.Source?

  public init() {}
}

/// The cat noticing things: one attention (``CatAttention``) fed by what happens around her and,
/// when nothing does, by looks of her own at the things in her room. She gets used to what
/// repeats, so the fourth turn of the camera in a minute gets an ear and not her head; anything
/// she notices wakes her up a little, and awake she looks about more often. The same seed and
/// the same calls give the same cat.
public struct CatNoticing: Sendable {
  public struct Context: Equatable, Sendable {
    /// On her feet and going somewhere: looks are shorter and need more to earn.
    public var moving: Bool
    /// From 0 awake to 1 asleep.
    public var drowse: Double
    /// Her curious trait, 0 to 1.
    public var curious: Double

    public init(moving: Bool = false, drowse: Double = 0, curious: Double = 0.5) {
      self.moving = moving
      self.drowse = drowse
      self.curious = curious
    }
  }

  /// How far the neck turns to a side at rest and on the move, and up and down, radians.
  public static let neck = (resting: 0.6, moving: 0.4, down: -0.25, up: 0.3)
  /// Seconds over which she forgets she has met a thing before.
  public static let forgetting = 90.0
  /// Seconds her arousal takes to settle back.
  public static let calming = 15.0

  public private(set) var attention = CatAttention.State.free
  /// From 0, half asleep, to 1, wide awake and quick.
  public private(set) var arousal = 0.3
  /// What stands around her that she may look at when nothing else has her, each with how much
  /// she cares for it as its salience; bearings as they are now.
  public var places: [CatStimulus] = []

  private var random: SplitMix64
  private var context = Context()
  private var now = 0.0
  /// How used she is to each source, 0 to 1, and when that was last worked out.
  private var familiar: [CatStimulus.Source: (level: Double, at: Double)] = [:]
  private var recent: [CatStimulus.Source] = []
  private var nextLook: Double
  private var nextSound: Double
  /// Where her head rests between looks: a little toward what she last watched.
  private var rest = (bearing: 0.0, elevation: 0.0)
  private var tilt = 0.0
  private var surveying = false
  private var blink = false

  public init(seed: UInt64) {
    random = SplitMix64(seed: seed ^ 0x4E4F_5449_4345)
    nextLook = 0
    nextSound = 0
    nextLook = random.next(in: 1.5...4)
    nextSound = random.next(in: 4...12)
  }

  /// How much of a thing's salience is left for her now: less the more often she met it lately,
  /// less when drowsy or busy walking, more for a curious cat.
  public func felt(_ stimulus: CatStimulus) -> Double {
    let used = familiarity(stimulus.source, at: now)
    // A look of her own choosing is worth what she chose it for.
    guard stimulus.sense != .own else { return stimulus.salience }
    return stimulus.salience * (1 - 0.75 * used) * (1 - 0.6 * context.drowse)
      * (0.8 + 0.4 * context.curious) * (context.moving ? 0.75 : 1)
  }

  private func familiarity(_ source: CatStimulus.Source, at time: Double) -> Double {
    guard let known = familiar[source] else { return 0 }
    return known.level * exp(-(time - known.at) / Self.forgetting)
  }

  /// Something happened at `now`. What she makes of it depends on how used to it she is.
  public mutating func notice(_ stimulus: CatStimulus, now: Double) {
    self.now = max(self.now, now)
    var felt = stimulus
    felt.salience = min(self.felt(stimulus), 1)
    if stimulus.sense != .own {
      let level = familiarity(stimulus.source, at: now)
      familiar[stimulus.source] = (level + 0.35 * (1 - level), now)
      // The small noises of a quiet room hardly wake her.
      arousal = min(1, arousal + (stimulus.source == .sound ? 0.15 : 0.4) * felt.salience)
    }
    send(.noticed(felt, at: now))
  }

  /// What she attends to moved: a finger, the camera.
  public mutating func track(_ source: CatStimulus.Source, bearing: Double, elevation: Double) {
    send(.moved(source, bearing: bearing, elevation: elevation))
  }

  /// It is no longer there.
  public mutating func lose(_ source: CatStimulus.Source, now: Double) {
    send(.gone(source, at: now))
  }

  private mutating func send(_ event: CatAttention.Event) {
    let (next, outputs) = CatAttention.transition(attention, event)
    attention = next
    for output in outputs {
      switch output {
      case .turned(let stimulus):
        // A big turn takes a blink with it, and now and then a curious cat tips her head at it.
        if abs(stimulus.bearing - rest.bearing) > 0.35 { blink = true }
        let tips = stimulus.sense != .own && random.next(in: 0...1) < 0.15 + 0.3 * context.curious
        tilt = tips ? (random.next(in: 0...1) < 0.5 ? -1 : 1) * random.next(in: 0.12...0.26) : 0
      case .released(let stimulus):
        blink = true
        rest = (0.55 * clamped(stimulus.bearing), 0.4 * stimulus.elevation)
        recent.append(stimulus.source)
        if recent.count > 2 { recent.removeFirst() }
        nextLook = now + CatAttention.letGo + gap()
      }
    }
  }

  /// Steps her to `now` and says what her attention asks of her body.
  public mutating func advance(to now: Double, _ context: Context = Context()) -> CatRegard {
    let dt = max(now - self.now, 0)
    self.now = now
    self.context = context
    let baseline = 0.3 * (1 - context.drowse)
    arousal = baseline + (arousal - baseline) * exp(-dt / Self.calming)
    blink = false

    if now >= nextSound {
      nextSound = now + random.next(in: 4...11)
      // Asleep she hears next to nothing, and with her mind on something she hears none of her own.
      if context.drowse < 0.9, attention == .free {
        let behind = random.next(in: 0...1) < 0.4
        let side = random.next(in: 0...1) < 0.5 ? -1.0 : 1.0
        notice(
          CatStimulus(
            .sound, .heard,
            bearing: side * (behind ? random.next(in: 1.4...2.6) : random.next(in: 0.3...1.2)),
            salience: random.next(in: 0.15...0.7), hold: random.next(in: 0.8...2)),
          now: now)
      }
    }
    send(.time(now))
    if case .free = attention, now >= nextLook, context.drowse < 0.8 {
      look(now)
      send(.time(now))
    }
    return regard(now)
  }

  /// Seconds between two looks of her own: mostly a few, now and then many, fewer the more awake.
  private mutating func gap() -> Double {
    // The more awake she is the more often her eyes go straight from one thing to the next.
    if random.next(in: 0...1) < 0.1 + 0.4 * arousal { return random.next(in: 0.1...0.5) }
    return 5 * exp(0.8 * gauss()) * max(1.6 - 1.4 * arousal, 0.35) * (1 + 0.8 * context.drowse)
      * (context.moving ? 0.8 : 1)
  }

  private mutating func gauss() -> Double {
    let u = max(random.next(in: 0...1), 1e-9)
    return (-2 * log(u)).squareRoot() * cos(2 * .pi * random.next(in: 0...1))
  }

  /// A look of her own: at one of the things around her, less likely one she has just looked at,
  /// or at nothing in particular.
  private mutating func look(_ now: Double) {
    let limit = context.moving ? Self.neck.moving : Self.neck.resting
    var choices = places.filter { abs($0.bearing) < limit + 0.5 }
    choices.append(
      CatStimulus(
        .nothing, .own, bearing: random.next(in: -0.5...0.5),
        elevation: random.next(in: -0.08...0.16),
        salience: 0.25, hold: 2))
    let weights = choices.map { $0.salience * (recent.contains($0.source) ? 0.25 : 1) }
    var draw = random.next(in: 0...1) * weights.reduce(0, +)
    var chosen = choices[choices.count - 1]
    for (choice, weight) in zip(choices, weights) {
      draw -= weight
      if draw <= 0 {
        chosen = choice
        break
      }
    }
    chosen.sense = .own
    chosen.salience = random.next(in: 0.45...0.7)
    chosen.hold = min(max(chosen.hold * exp(0.5 * gauss()), 0.6), 7)
    // On the move a look is a glance; arrived, a look about is neither a glance nor a stare.
    if surveying {
      chosen.hold = min(max(chosen.hold, 0.9), 1.8)
    } else if context.moving {
      chosen.hold *= 0.4
    }
    notice(chosen, now: now)
  }

  /// A look about on arriving somewhere: the next look of her own comes now. Returns the seconds
  /// it will take, for whoever waits for it.
  public mutating func survey(now: Double) -> Double {
    // Whatever she glanced at on the way is dropped for it.
    attention = .free
    nextLook = now
    surveying = true
    _ = advance(to: now, context)
    surveying = false
    guard case .watching(let stimulus, _) = attention else { return 0.6 }
    return stimulus.hold + 0.25
  }

  /// A number in `range` from her dice, for whoever plays her to vary a wait by.
  public mutating func draw(in range: ClosedRange<Double>) -> Double {
    random.next(in: range)
  }

  private func clamped(_ bearing: Double) -> Double {
    let limit = context.moving ? Self.neck.moving : Self.neck.resting
    return min(max(bearing, -limit), limit)
  }

  private func regard(_ now: Double) -> CatRegard {
    var r = CatRegard()
    r.blink = blink
    r.headYaw = rest.bearing
    r.headPitch = rest.elevation
    r.alert = arousal
    switch attention {
    case .free:
      break
    case .releasing(let stimulus, let since):
      r.source = stimulus.source
      r.stillness = 0.5 * (1 - min((now - since) / CatAttention.letGo, 1))
    case .pricked(let stimulus, _, _):
      r.source = stimulus.source
      // The ear on its side swings its opening round to it, the further back the more; the other
      // follows only for something behind her.
      let behind = Self.smooth(abs(stimulus.bearing), 0.6, 2.2)
      let near = 0.35 + 0.6 * behind
      let far = 0.35 * behind
      (r.earLeft, r.earRight) = stimulus.bearing < 0 ? (near, far) : (far, near)
      r.stillness = 0.9
      r.alert = max(arousal, stimulus.salience)
      r.snap = 0.3 + 0.7 * stimulus.salience
    case .watching(let stimulus, let since):
      r.source = stimulus.source
      let elapsed = now - since
      r.headYaw = clamped(stimulus.bearing)
      r.headPitch = min(max(stimulus.elevation, Self.neck.down), Self.neck.up)
      r.headRoll = tilt * Self.smooth(elapsed, 0.35, 0.8)
      // Past what the neck turns, the ear on that side stays turned back to it.
      let past = Self.smooth(abs(stimulus.bearing), 0.6, 2.2)
      let forward = -0.25 * stimulus.salience
      (r.earLeft, r.earRight) =
        stimulus.bearing < 0 ? (forward + 0.9 * past, forward) : (forward, forward + 0.9 * past)
      r.chest = 0.3 * Self.smooth(elapsed, 0.4, 1.2)
      r.lean =
        stimulus.sense == .heard ? 0 : 0.03 * stimulus.salience * Self.smooth(elapsed, 0.3, 1)
      // Stock still at first, easing as her interest goes.
      let share = min(elapsed / max(stimulus.hold, 0.01), 1)
      r.stillness = 1 - 0.5 * Self.smooth(share, 0.4, 1)
      r.tailTip = stimulus.salience * Self.smooth(elapsed, 0.5, 1.5)
      r.alert = max(arousal, stimulus.salience)
      r.snap = 0.3 + 0.7 * stimulus.salience
    }
    return r
  }

  private static func smooth(_ x: Double, _ low: Double, _ high: Double) -> Double {
    let t = min(max((x - low) / (high - low), 0), 1)
    return t * t * (3 - 2 * t)
  }
}
