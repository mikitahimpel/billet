import Foundation

/// A small thing a settled cat does of her own accord, between the things that take her attention.
public enum CatFidget: String, CaseIterable, Hashable, Sendable {
  /// One ear flicks out and back.
  case earFlick
  /// The tail's tip flicks to a side.
  case tailFlick
  /// The tail's tip curls up and stays a while.
  case tailCurl
  /// A slow blink, at whoever watches if she is looking at them.
  case slowBlink
  /// The head tips to a side, as at something odd.
  case tilt
  /// A quick shake of the head.
  case shake
  case yawn
  /// A deep breath let out as she settles.
  case sigh
  /// She settles her weight another way.
  case shift
  /// She washes her chest.
  case groom

  /// One of the larger acts, which whoever directs her chooses when she is directed.
  public var large: Bool {
    switch self {
    case .tilt, .shake, .yawn, .groom: true
    case .earFlick, .tailFlick, .tailCurl, .slowBlink, .sigh, .shift: false
    }
  }

  /// The least seconds between two of the same.
  public var rest: Double {
    switch self {
    case .earFlick: 3
    case .tailFlick, .shift: 8
    case .slowBlink, .tilt: 12
    case .tailCurl, .sigh: 25
    case .shake: 40
    case .groom: 45
    case .yawn: 60
    }
  }
}

/// Chooses her fidgets: which and when, by how awake, sleepy and content she is, never the same
/// one time after time, and none at all while something holds her still. Letting go of something
/// is when a cat most often does one, so a release brings the next one forward. Seeded.
public struct CatFidgeting: Sendable {
  public struct Mood: Equatable, Sendable {
    /// From 0 half asleep to 1 wide awake (``CatNoticing/arousal``).
    public var arousal: Double
    /// From 0 awake to 1 asleep.
    public var drowse: Double
    public var contentment: Double
    /// How still her attention holds her, 0 to 1.
    public var stillness: Double
    /// She has just sat or lain down.
    public var settling: Bool
    /// Something else chooses her larger acts.
    public var directed: Bool

    public init(
      arousal: Double = 0.3, drowse: Double = 0, contentment: Double = 0.5, stillness: Double = 0,
      settling: Bool = false, directed: Bool = false
    ) {
      self.arousal = arousal
      self.drowse = drowse
      self.contentment = contentment
      self.stillness = stillness
      self.settling = settling
      self.directed = directed
    }
  }

  private var random: SplitMix64
  private var next: Double
  private var last: [CatFidget: Double] = [:]
  private var recent: [CatFidget] = []
  private var wasStill = false

  public init(seed: UInt64) {
    random = SplitMix64(seed: seed ^ 0x4649_4447_4554)
    next = 0
    next = random.next(in: 3...8)
  }

  /// How likely each fidget is now, before her memory of the last ones: all zero while she is held.
  public static func weights(_ mood: Mood) -> [CatFidget: Double] {
    guard mood.stillness < 0.5, mood.drowse < 0.9 else { return [:] }
    let awake = mood.arousal * (1 - mood.drowse)
    let own = mood.directed ? 0.0 : 1.0
    return [
      .earFlick: 1 + awake,
      .tailFlick: 0.4 + 0.8 * awake,
      .tailCurl: 0.3 + 0.5 * mood.contentment,
      .slowBlink: 0.3 + 0.9 * mood.contentment + 0.5 * mood.drowse,
      .tilt: own * (0.1 + 0.5 * awake),
      .shake: own * 0.1,
      .yawn: own * (0.05 + 1.2 * mood.drowse),
      .groom: own * 0.35 * (1 - mood.drowse),
      .sigh: mood.settling ? 3 : 0.15 + 0.4 * mood.drowse,
      .shift: 0.5,
    ]
  }

  /// The fidget that starts at `now`, if one does.
  public mutating func advance(to now: Double, _ mood: Mood) -> CatFidget? {
    let still = mood.stillness >= 0.5
    defer { wasStill = still }
    // Coming out of a stare the next one is close.
    if wasStill, !still { next = min(next, now + random.next(in: 0.2...1.2)) }
    if mood.settling { next = min(next, now + 0.6) }
    guard now >= next else { return nil }
    let weights = Self.weights(mood)
    let choices = CatFidget.allCases.compactMap { fidget -> (CatFidget, Double)? in
      guard let weight = weights[fidget], weight > 0 else { return nil }
      if let at = last[fidget], now - at < fidget.rest { return nil }
      return (fidget, weight * (recent.contains(fidget) ? 0.2 : 1))
    }
    // Sleepy and calm she fidgets less often; a gap is mostly several seconds and now and then long.
    let u = max(random.next(in: 0...1), 1e-9)
    let gauss = (-2 * log(u)).squareRoot() * cos(2 * .pi * random.next(in: 0...1))
    next = now + 6 * exp(0.7 * gauss) * (1.5 - mood.arousal) * (1 + mood.drowse)
    guard !choices.isEmpty else { return nil }
    var draw = random.next(in: 0...1) * choices.reduce(0) { $0 + $1.1 }
    var chosen = choices[choices.count - 1].0
    for (fidget, weight) in choices {
      draw -= weight
      if draw <= 0 {
        chosen = fidget
        break
      }
    }
    last[chosen] = now
    recent.append(chosen)
    if recent.count > 2 { recent.removeFirst() }
    return chosen
  }
}
