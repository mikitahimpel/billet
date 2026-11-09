import Foundation

extension CatBrain {
  // MARK: - Reading

  public var stack: CatBrainStack {
    CatBrainStack(vitality: vitality, step: activity.step, interaction: echo?.interaction)
  }

  /// The frame for the brain as it is, with `live` from this phone's own touch over it.
  public func frame(live: CatInteraction? = nil) -> CatBrainFrame {
    var interaction = echo?.interaction
    if let live, live.priority >= interaction?.priority ?? .min { interaction = live }
    // A sulk keeps its back turned to a touch until it forgives, at the second pet.
    if activity.step == .sulk, case .petted = interaction { interaction = nil }
    var stack = stack
    stack.interaction = interaction
    let feeling = feeling
    var action =
      interaction.map { Self.clip($0, asleep: vitality == .asleep) }
      ?? CatStatechart.clip(activity.step)
    // A hungry cat begs at a finger instead of only watching it.
    if interaction == .followFinger, feeling == .hungry || feeling == .hangry { action = .wave }
    let voice = interaction == nil ? Self.voice(activity.step, feeling: feeling) : nil
    return CatBrainFrame(
      stack: stack, action: action, target: interaction == nil ? activity.target : .stay,
      gaze: interaction.map { _ in CatGaze.camera } ?? activity.gaze,
      pace: CatStatechart.pace(activity.step), stepStart: activity.start, stepEnd: activity.end,
      eager: eager, tempo: temperament?.tempo ?? 1, amplitude: temperament?.amplitude ?? 1,
      personalSpace: upbringing.personalSpace(from: temperament?.personalSpace ?? 0.3),
      tricks: upbringing.tricks, feeling: feeling, voice: voice,
      voiceEvery: voice.flatMap { Self.voiceEvery($0, step: activity.step) },
      purring: purrs(interaction))
  }

  public var feeling: CatFeeling {
    CatFeeling.of(
      needs: life.needs, mood: life.mood, asleep: vitality == .asleep,
      sleepy: vitality == .drowsy || life.pressure > config.drowsyAbove, temperament: temperament,
      config: lifeConfig)
  }

  /// How hungry it acts, from 0 up, after its temperament's drama.
  public var hunger: Double {
    CatFeeling.hunger(life.needs.full, temperament: temperament, config: lifeConfig)
  }

  /// The sound a step makes for a cat that feels this way.
  static func voice(_ step: CatActivityStep, feeling: CatFeeling) -> CatVoice? {
    let hungry = feeling == .hungry || feeling == .hangry
    if step == .yowl { return .yowl }
    if step == .dropToy { return .chirp }
    if asks.contains(step) { return hungry ? .meow : nil }
    if rages.contains(step) { return feeling == .hangry ? .yowl : nil }
    if step == .seekYou { return feeling == .lonely || feeling == .bored ? .meow : nil }
    return nil
  }

  /// Steps that meow for food, and tantrum steps that yowl.
  static let asks: Set<CatActivityStep> = [.waitByBowl, .pawBowl, .beg]
  static let rages: Set<CatActivityStep> = [.knockOff, .flop]

  /// How often a long step's sound comes again, in seconds, or nil for once.
  static func voiceEvery(_ voice: CatVoice, step: CatActivityStep) -> Double? {
    repeats[step]
  }

  private static let repeats: [CatActivityStep: Double] = [.waitByBowl: 7, .beg: 3.5, .flop: 4]

  /// Whether it purrs: being petted, or a happy cat close to you. A sulk is never petted.
  private func purrs(_ interaction: CatInteraction?) -> Bool {
    guard vitality != .asleep else { return false }
    if case .petted = interaction { return true }
    guard interaction == nil, Self.purrSteps.contains(activity.step) else { return false }
    return feeling == .happy || feeling == .content
  }

  static let purrSteps: Set<CatActivityStep> = [.bellyUp, .knead, .slowBlink, .rub]

  /// Whether the cat is in the mood to bat at a finger: awake, not napping or eating, and keen
  /// to play by its nature and by how long since its last game. A playful cat nearly always is;
  /// an even one once its Playful need has dropped below about half; a lazy one rarely.
  public var eager: Bool {
    guard vitality == .awake, activity.step.group != .rest, activity.step.group != .eat else {
      return false
    }
    let want = NeedFocus.urgency(life.needs[.playful])
    return 0.5 * want + 0.5 * personality.playful >= Self.eagerAbove
  }

  static let eagerAbove = 0.4
  /// A meal from a full bowl.
  static let meal: [CatActivityStep] = [.walkToBowl, .eat, .lickLips]
  /// Below this Full, a cat whose mealtime it is goes to wait by the bowl.
  static let waitsBelow = 0.85

  static func clip(_ interaction: CatInteraction, asleep: Bool) -> CatAction {
    switch interaction {
    case .petted: asleep ? .sleep : .happy
    case .held: .dangle
    case .toy: .crouchWiggle
    case .called: .walk
    case .fed: .eat
    case .followFinger: .sit
    case .greeting: .headbutt
    case .batting: .bat
    }
  }

  /// The local hour at `t`.
  public func hour(at t: Double) -> Double {
    var hour = (t + Double(utcOffset)).truncatingRemainder(dividingBy: 86400) / 3600
    if hour < 0 { hour += 24 }
    return hour
  }

  /// When the next decision falls; `advance(to:)` does nothing before it.
  public var nextDecision: Double {
    var next = min(nextCheck, nextDay)
    if let echo { next = min(next, echo.until) } else { next = min(next, activity.end) }
    if let event = pending.first { next = min(next, event.at.timeIntervalSince1970) }
    return next
  }
}
