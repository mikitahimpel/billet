import Foundation

/// How big the pair's shared flame has grown. A broken streak rests as an ember, which still
/// glows: the flame never goes out.
///
/// The stages are the flame's own and do not follow ``HouseStage``.
public enum FlameStage: Int, CaseIterable, Comparable, Sendable {
  /// No streak today: a warm coal that one day together lights again.
  case ember
  /// 1–2 days.
  case spark
  /// 3–6 days.
  case candle
  /// 7–13 days.
  case steady
  /// 14–29 days.
  case lantern
  /// 30–59 days.
  case hearth
  /// 60–99 days.
  case fire
  /// 100–364 days.
  case beacon
  /// 365 days and on.
  case everglow

  /// The day each stage begins.
  public var firstDay: Int {
    switch self {
    case .ember: 0
    case .spark: 1
    case .candle: 3
    case .steady: 7
    case .lantern: 14
    case .hearth: 30
    case .fire: 60
    case .beacon: 100
    case .everglow: 365
    }
  }

  public init(streak: Int) {
    self = Self.allCases.last { $0.firstDay <= streak } ?? .ember
  }

  /// The stage after this one, or `nil` at the last.
  public var next: FlameStage? {
    FlameStage(rawValue: rawValue + 1)
  }

  /// What the flame is at this stage, for the scene's caption and VoiceOver.
  public var title: String {
    switch self {
    case .ember: "A warm ember"
    case .spark: "A tiny spark"
    case .candle: "A candle flame"
    case .steady: "A steady flame"
    case .lantern: "A lantern glow"
    case .hearth: "A little hearth"
    case .fire: "A hearth fire"
    case .beacon: "A beacon"
    case .everglow: "An everglow"
    }
  }

  public static func < (lhs: FlameStage, rhs: FlameStage) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// The flame for one streak: its stage, how far it has grown towards the next, and the soft
/// words that go with it.
public struct StreakFlame: Equatable, Sendable {
  public let streak: Int

  public init(streak: Int) {
    self.streak = max(streak, 0)
  }

  public var stage: FlameStage { FlameStage(streak: streak) }

  /// True when there is no streak today, so the flame rests as an ember.
  public var isEmber: Bool { stage == .ember }

  /// The day the next stage begins, or `nil` past the last.
  public var nextMilestone: Int? { stage.next?.firstDay }

  /// How grown the flame is, from 0 (an ember) to 1 (the last stage), rising evenly through each
  /// stage so the flame grows a little every day rather than in jumps. Past the last stage it
  /// keeps creeping up for another year, to a little over 1.
  public var growth: Double {
    let stages = Double(FlameStage.allCases.count - 1)
    let stage = stage
    guard let next = stage.next else {
      let beyond = Double(streak - stage.firstDay) / 365
      return 1 + 0.1 * min(beyond, 1)
    }
    let span = Double(next.firstDay - stage.firstDay)
    let into = Double(streak - stage.firstDay) / span
    return (Double(stage.rawValue) + into) / stages
  }

  /// The day count and what comes next, with no pressure: "12 days · next glow at 14".
  public var caption: String {
    if isEmber { return "Resting as a warm ember" }
    let days = streak == 1 ? "1 day" : "\(streak) days"
    guard let nextMilestone else { return "\(days) · glowing for good" }
    return "\(days) · next glow at \(nextMilestone)"
  }
}

/// Who has added to the flame today, for its two tongues.
public struct FlameContributions: Equatable, Sendable {
  public var mine: Bool
  public var theirs: Bool

  public init(mine: Bool = false, theirs: Bool = false) {
    self.mine = mine
    self.theirs = theirs
  }

  /// The line under the caption, or `nil` when neither has yet. Never a nudge.
  public var line: String? {
    switch (mine, theirs) {
    case (true, true): "You both added to it today"
    case (true, false): "You added to it today"
    case (false, true): "Your partner added to it today"
    case (false, false): nil
    }
  }
}

/// What opening the flame should show this time.
public struct FlameVisit: Equatable, Sendable {
  /// A stage reached since the last visit, celebrated once with sparks.
  public var milestone: FlameStage?
  /// The flame was an ember last time and is lit again, so it catches with a small burst.
  public var rekindled: Bool
  /// A note came since the last visit, so the flame brightens with a gentle pulse.
  public var pulse: Bool

  public init(milestone: FlameStage? = nil, rekindled: Bool = false, pulse: Bool = false) {
    self.milestone = milestone
    self.rekindled = rekindled
    self.pulse = pulse
  }

  /// Nothing new since the last visit.
  public static let quiet = FlameVisit()
}

/// What this phone remembers of the last time the flame was opened, so each milestone is
/// celebrated once and a rekindling is seen once.
public struct FlameMemory: Codable, Equatable, Sendable {
  /// The streak at the last visit, or `nil` before the first.
  public private(set) var lastStreak: Int?
  /// The highest stage celebrated in the current run. A run that ends starts this over, so the
  /// next run's stages are celebrated too.
  public private(set) var celebrated: Int
  /// The newest note seen at the last visit.
  public private(set) var lastNote: UUID?

  public init() {
    lastStreak = nil
    celebrated = FlameStage.ember.rawValue
    lastNote = nil
  }

  /// Opens the flame at `streak` with `newestNote` the newest note on this phone, and returns
  /// what to show. Remembers the visit, so the same streak and note show nothing new next time.
  public mutating func visit(streak: Int, newestNote: UUID?) -> FlameVisit {
    let flame = StreakFlame(streak: streak)
    let stage = flame.stage
    var visit = FlameVisit()
    visit.pulse = newestNote != nil && newestNote != lastNote && lastStreak != nil

    if let lastStreak {
      // A streak lower than last time, or one that was resting, means a run ended in between.
      let runEnded = flame.streak < lastStreak || lastStreak == 0
      if runEnded { celebrated = FlameStage.ember.rawValue }
      if !flame.isEmber, runEnded {
        visit.rekindled = true
        // The rekindling is this visit's celebration.
        celebrated = stage.rawValue
      }
    }
    if !visit.rekindled, stage > .ember, stage.rawValue > celebrated {
      visit.milestone = stage
      celebrated = stage.rawValue
    }
    lastStreak = flame.streak
    lastNote = newestNote ?? lastNote
    return visit
  }
}
