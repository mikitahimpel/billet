import Foundation

/// What her tail says. A cat's tail is carried by her mood before anything else moves it: up with
/// the tip hooked over to someone she is glad to see, low and nearly still when something has her
/// whole attention, slack and slow when she is half asleep.
public enum CatTailMood: String, CaseIterable, Hashable, Sendable {
  case easy
  case greeting
  case intent
  case drowsy
}

/// How the tail is held and moved, for the body to pose.
public struct CatTailCarriage: Equatable, Sendable {
  /// From -1, held low, through 0, as her posture has it, to 1, straight up.
  public var raise: Double
  /// From 0 to 1: the tip curled over, the question mark of a greeting.
  public var hook: Double
  /// A factor on how wide the tail's wave is.
  public var swing: Double
  /// A factor on how fast the wave runs.
  public var pace: Double
  /// From 0 to 1: a fast small tremble along the whole tail, the first moment of a greeting.
  public var quiver: Double

  public init(raise: Double, hook: Double, swing: Double, pace: Double, quiver: Double = 0) {
    self.raise = raise
    self.hook = hook
    self.swing = swing
    self.pace = pace
    self.quiver = quiver
  }

  public static let easy = CatTailCarriage(raise: 0, hook: 0, swing: 1, pace: 1)
}

extension CatTailMood {
  /// Where the mood takes the tail once it has settled into it.
  public var carriage: CatTailCarriage {
    switch self {
    case .easy: .easy
    case .greeting: CatTailCarriage(raise: 1, hook: 0.7, swing: 0.4, pace: 1.2)
    case .intent: CatTailCarriage(raise: -0.5, hook: 0, swing: 0.15, pace: 0.6)
    case .drowsy: CatTailCarriage(raise: -0.3, hook: 0, swing: 0.4, pace: 0.5)
    }
  }
}

/// Carries her tail by her mood: reads what has her attention and how awake she is, and eases the
/// tail there, up quickly and down slowly as a cat's does. A greeting outlasts the look that began
/// it, since she keeps the tail up while she comes over.
public struct CatTail: Sendable {
  public struct Context: Equatable, Sendable {
    /// What she attends to, if anything (``CatRegard/source``).
    public var source: CatStimulus.Source?
    /// How still her attention holds her, 0 to 1.
    public var stillness: Double
    /// From 0 half asleep to 1 wide awake (``CatNoticing/arousal``).
    public var arousal: Double
    public var contentment: Double
    /// From 0 awake to 1 asleep.
    public var drowse: Double
    public var moving: Bool
    /// What she attends to lies ahead of her, within what she would walk toward.
    public var ahead: Bool

    public init(
      source: CatStimulus.Source? = nil, stillness: Double = 0, arousal: Double = 0.3,
      contentment: Double = 0.5, drowse: Double = 0, moving: Bool = false, ahead: Bool = false
    ) {
      self.source = source
      self.stillness = stillness
      self.arousal = arousal
      self.contentment = contentment
      self.drowse = drowse
      self.moving = moving
      self.ahead = ahead
    }
  }

  /// Seconds a greeting lasts after what began it has gone.
  public static let greetingLinger = 2.5
  /// Seconds the tremble of a greeting takes to die away.
  public static let quiverFade = 1.2
  /// Seconds the tail takes to come most of the way up, and down.
  public static let rise = 0.3
  public static let fall = 0.9

  public private(set) var mood = CatTailMood.easy
  public private(set) var carriage = CatTailCarriage.easy
  private var greetedFor: Double?
  private var sinceGreeted = Double.infinity

  public init() {}

  /// The mood the moment asks for, before a greeting's linger. Sleepiness comes first: a dozing
  /// cat greets nobody. She greets whoever touches her and the partner coming in; the one who
  /// watches her only when she is content, and then at rest when it is news to her and on her
  /// feet when she is coming their way.
  public static func asked(_ context: Context) -> CatTailMood {
    if context.drowse >= 0.6 { return .drowsy }
    switch context.source {
    case .touch, .partner:
      return .greeting
    case .viewer:
      guard context.contentment >= 0.3 else { return .easy }
      return (context.moving ? context.ahead : context.arousal >= 0.55) ? .greeting : .easy
    case .place, .noise, .sound:
      return context.stillness >= 0.5 ? .intent : .easy
    case .destination, .nothing, nil:
      return .easy
    }
  }

  /// Steps `dt` seconds; returns how the tail is carried now.
  @discardableResult
  public mutating func advance(by dt: Double, _ context: Context) -> CatTailCarriage {
    let asked = Self.asked(context)
    if asked == .greeting {
      greetedFor = (greetedFor ?? 0) + dt
      sinceGreeted = 0
    } else {
      sinceGreeted += dt
      if sinceGreeted >= Self.greetingLinger || asked == .drowsy { greetedFor = nil }
    }
    mood = greetedFor != nil ? .greeting : asked
    var target = mood.carriage
    if let greetedFor { target.quiver = max(0, 1 - greetedFor / Self.quiverFade) }

    func ease(_ value: inout Double, _ to: Double, seconds: Double) {
      value += (to - value) * (1 - exp(-dt / seconds))
    }
    let rising = target.raise > carriage.raise
    ease(&carriage.raise, target.raise, seconds: rising ? Self.rise : Self.fall)
    ease(&carriage.hook, target.hook, seconds: Self.fall)
    ease(&carriage.swing, target.swing, seconds: Self.fall)
    ease(&carriage.pace, target.pace, seconds: Self.fall)
    carriage.quiver = target.quiver
    return carriage
  }
}
