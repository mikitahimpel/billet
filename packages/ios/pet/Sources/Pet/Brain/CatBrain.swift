import Foundation

/// The cat's brain: a hierarchical state machine of vitality, activity and interaction, with
/// utility choosing the activity. Pure in the events, time and seed: decisions fall on a fixed time
/// grid with dice from ``BrainDice``, so both phones and the widget fold the same cat untended.
public struct CatBrain: Sendable {
  public let seed: UInt64
  public let config: CatBrainConfig
  /// Fixed for life; nil for a cat with none, as in tests.
  public let temperament: CatTemperament?
  /// Its temperament's personality, with its seed's own touch.
  public let nature: CatPersonality
  /// The nature, moved by the last few days.
  public private(set) var personality: CatPersonality
  /// Where it likes to rest, from yesterday and today.
  public private(set) var memory: CatMemory
  /// Learned from how the partners treat it, as of today's start.
  public private(set) var upbringing: CatUpbringing
  public private(set) var room: RoomAffordances
  public private(set) var weather: ViewWeather

  /// Seconds since 1970.
  public private(set) var time: Double
  public private(set) var vitality: CatVitality = .awake
  private var vitalitySince: Double
  var activity: Activity
  var echo: (interaction: CatInteraction, until: Double)?
  /// The activity as it was when an interaction broke in, to come back to afterwards.
  private var history: Activity?
  var life: CatLifeSample
  var focus: NeedFocus
  var nextCheck: Double
  var nextDay: Double
  var pending: [LifeEvent] = []
  var lastSeen: [String: Double] = [:]
  private var born: Double
  var inspected = Set<String>()
  /// Whether the sulk under way has ignored a touch already; the next one is forgiven.
  private var snubbed = false
  public private(set) var recent: [CatEpisode] = []
  public private(set) var transitions: [CatBrainTransition] = []
  /// The last utility scores worked out, in the order of ``CatActivityGroup/chosen``.
  public private(set) var scores: [CatUtilityScore] = []

  struct Activity: Hashable, Sendable {
    var step: CatActivityStep
    var start: Double
    var end: Double
    var script: [CatActivityStep]
    var index: Int
    var groupStart: Double
    var napSpot: RoomAffordance.Kind?
    var inspecting: RoomAffordance?
    var target: CatTarget
    var gaze: CatGaze
  }

  /// A brain starting at `start` from its canonical state for `life` there. `personality` is the
  /// one it was born with, and `day` what experience has made of it by `start`.
  public init(
    seed: UInt64, temperament: CatTemperament? = nil, personality: CatPersonality? = nil,
    day: CatDay? = nil, room: RoomAffordances,
    weather: ViewWeather = .clear, start: Double, life: CatLifeSample, utcOffset: Int,
    lifeConfig: LifeConfig = .standard, config: CatBrainConfig = .standard
  ) {
    self.seed = seed
    self.config = config
    self.temperament = temperament
    nature = personality ?? Self.nature(seed: seed, temperament: temperament)
    self.personality = day?.personality ?? nature
    memory = day?.memory ?? CatMemory()
    upbringing = day?.upbringing ?? .none
    self.room = room
    self.weather = weather
    self.utcOffset = utcOffset
    self.lifeConfig = lifeConfig
    let start = Self.quantize(start, config.decisionStep)
    time = start
    born = start
    vitalitySince = start
    self.life = life
    focus = NeedFocus(config: lifeConfig, seed: seed ^ 0x464F_4355_53)
    nextCheck = start
    nextDay = start
    activity = Activity(
      step: .sit, start: start, end: start, script: [.sit], index: 0, groupStart: start,
      napSpot: nil, inspecting: nil, target: .home, gaze: .ahead)
    nextDay = dayStart(after: start)
    startDay(at: start, record: false)
  }

  public static func nature(seed: UInt64, temperament: CatTemperament?) -> CatPersonality {
    let seeded = CatPersonality.seeded(seed)
    return temperament?.nature(from: seeded) ?? seeded
  }

  let utcOffset: Int
  let lifeConfig: LifeConfig

  // MARK: - Driving

  /// Takes events to fold. Only events after the brain's time count; an earlier one needs a
  /// replay from before it, which ``CatBrainRunner`` does.
  public mutating func schedule(_ events: some Sequence<LifeEvent>) {
    let fresh = events.filter { $0.at.timeIntervalSince1970 > time - 1e-9 }
    guard !fresh.isEmpty else { return }
    var known = Set(pending.map(\.id))
    pending += fresh.filter { known.insert($0.id).inserted }
    pending.sort(by: LifeEvent.precedes)
  }

  /// Notes who did something before the brain began, for how long each partner has been away.
  public mutating func remember(_ events: some Sequence<LifeEvent>) {
    for event in events { see(event) }
  }

  public mutating func setRoom(_ room: RoomAffordances, weather: ViewWeather) {
    self.room = room
    self.weather = weather
  }

  public mutating func advance(to now: Double, life sampler: inout CatLifeSampler) {
    while true {
      let next = nextDecision
      guard next <= now else { return }
      time = max(time, next)
      if nextDay <= time {
        nextDay = dayStart(after: time)
        let day = Self.opening(
          at: time, seed: seed, temperament: temperament, nature: nature, room: room,
          weather: weather, sampler: &sampler,
          utcOffset: utcOffset, config: config)
        personality = day.personality
        memory = day.memory
        upbringing = day.upbringing
        life = sampler.sample(at: time)
        startDay(at: time, record: true)
        continue
      }
      if let event = pending.first, event.at.timeIntervalSince1970 <= time {
        pending.removeFirst()
        life = sampler.sample(at: time)
        apply(event)
        continue
      }
      if let echo, echo.until <= time {
        endEcho()
        continue
      }
      if echo == nil, activity.end <= time {
        life = sampler.sample(at: time)
        _ = focus.update(life.needs)
        stepEnded()
        continue
      }
      if nextCheck <= time {
        nextCheck = Self.quantize(time + config.checkEvery, config.checkEvery)
        life = sampler.sample(at: time)
        _ = focus.update(life.needs)
        checkVitality()
      }
    }
  }

  // MARK: - Days

  /// The next local `dayStartHour` after `t`.
  func dayStart(after t: Double) -> Double {
    let local = t + Double(utcOffset) - config.dayStartHour * 3600
    let day = (local / 86400).rounded(.down) + 1
    return day * 86400 + config.dayStartHour * 3600 - Double(utcOffset)
  }

  /// The canonical state a day starts from: asleep in its nap spot at night, sitting otherwise.
  private mutating func startDay(at t: Double, record: Bool) {
    let before = stack
    echo = nil
    history = nil
    recent.removeAll(keepingCapacity: true)
    // Nothing the trajectory learned crosses the day line, so a fold from today's start gives
    // the same cat as one that has run for a week.
    inspected.removeAll(keepingCapacity: true)
    snubbed = false
    focus = NeedFocus(config: lifeConfig, seed: seed ^ 0x464F_4355_53)
    vitalitySince = t
    if life.asleep {
      vitality = .asleep
      let spot = chooseNapSpot(at: t)
      activity = makeActivity(
        script: [.curl, .wake], index: 0, at: t, groupStart: t, napSpot: spot)
    } else {
      vitality = .awake
      activity = makeActivity(script: [.sit], index: 0, at: t, groupStart: t, napSpot: nil)
    }
    nextCheck = Self.quantize(t + config.checkEvery, config.checkEvery)
    if record { log(before, cause: .dayStart) }
  }

  // MARK: - Events

  private mutating func see(_ event: LifeEvent) {
    lastSeen[event.by] = max(lastSeen[event.by] ?? 0, event.at.timeIntervalSince1970)
  }

  private mutating func apply(_ event: LifeEvent) {
    see(event)
    let t = time
    switch event.kind {
    case .note:
      let curled = activity.step == .curl
      countRest(at: t)
      echo = nil
      history = nil
      enter(script: curled ? [.wake, .carryNote] : [.carryNote], at: t, cause: .event)
      if vitality == .asleep { moveVitality(to: .drowsy, at: t) }
    case .pet:
      if activity.step == .sulk, echo == nil {
        if !snubbed {
          // The first touch is ignored.
          snubbed = true
          return
        }
        // The second is forgiven, with a head-bump.
        if let spot = spot { memory.petted(at: spot) }
        finishGroup(at: t)
        enter(script: [.seekYou, .rub], at: t, cause: .event)
        return
      }
      if let spot = spot { memory.petted(at: spot) }
      interrupt(with: .petted(.back), for: config.petEcho, at: t)
    case .feed:
      if activity.step.group == .eat, activity.script != Self.meal {
        // The meal it waited, begged or raged for: it goes to eat once the bowl is full.
        finishGroup(at: t)
        enter(script: Self.meal, at: t, cause: .event)
      }
      interrupt(with: .fed, for: config.feedEcho, at: t)
    case .play:
      echo = nil
      history = nil
      let curled = activity.step == .curl
      countRest(at: t)
      enter(script: curled ? [.wake, .stalk, .pounce] : [.stalk, .pounce], at: t, cause: .event)
      if vitality == .asleep { moveVitality(to: .drowsy, at: t) }
    case .sleep:
      echo = nil
      history = nil
      if activity.step != .curl {
        enterRest(at: t, cause: .event)
      }
    case .shoo:
      // Off the desk or the cardigan with a start; elsewhere a shoo means nothing to it.
      guard activity.step.group == .mischief else { return }
      echo = nil
      history = nil
      finishGroup(at: t)
      enter(script: [.startle], at: t, cause: .event)
    }
  }

  /// An interaction breaks in: the activity is kept as history and frozen until it ends.
  private mutating func interrupt(
    with interaction: CatInteraction, for seconds: Double, at t: Double
  ) {
    let before = stack
    if echo == nil { history = activity }
    echo = (interaction, Self.quantize(t + seconds, config.decisionStep))
    log(before, cause: .interaction)
  }

  /// The interaction is over: the activity comes back from its history. A step whose time is not
  /// yet up goes on as if never left, such as a nap; one that ran out moves on.
  private mutating func endEcho() {
    let before = stack
    let ended = echo?.interaction
    echo = nil
    guard let history else { return }
    self.history = nil
    activity = history
    log(before, cause: .history)
    // An awake cat answers a pet as its temperament does; a napping one sleeps on.
    if case .petted = ended, vitality == .awake, activity.step != .curl,
      let answer = temperament?.afterTouch
    {
      finishGroup(at: time)
      enter(script: answer, at: time, cause: .event)
      return
    }
    if activity.end <= time { stepEnded() }
  }

  // MARK: - Steps

  private var spot: RoomAffordance.Kind? {
    if activity.step.group == .rest, let napSpot = activity.napSpot { return napSpot }
    switch activity.target {
    case .affordance(let kind): return kind
    case .stay, .home, .camera, .roam: return nil
    }
  }

  /// Remembers the time curled up or kneading in this nap spot.
  private mutating func countRest(at t: Double) {
    guard activity.step == .curl || activity.step == .knead, let napSpot = activity.napSpot else {
      return
    }
    memory.rested(at: napSpot, seconds: t - activity.start)
  }

  private mutating func stepEnded() {
    let t = time
    countRest(at: t)
    // A cat curled up at night sleeps on: the curl renews without a move.
    if activity.step == .curl,
      life.asleep || vitality == .asleep && life.pressure > config.drowsyAbove
    {
      activity.start = t
      activity.end = Self.quantize(
        t + BrainDice.range(CatStatechart.duration(.curl), dice(t, 11)), config.decisionStep)
      return
    }
    let next = activity.index + 1
    guard next < activity.script.count else {
      finishGroup(at: t)
      choose(at: t, cause: .chosen)
      return
    }
    if activity.step != .curl, let better = preemption(at: t) {
      finishGroup(at: t)
      enter(group: better, at: t, cause: .preempted)
      return
    }
    let before = stack
    // A script that crosses into another group, as a wake into a game, starts that group's clock.
    let crosses = activity.script[next].group != activity.step.group
    activity = makeActivity(
      script: activity.script, index: next, at: t,
      groupStart: crosses ? t : activity.groupStart,
      napSpot: activity.napSpot, inspecting: activity.inspecting)
    log(before, cause: .scriptNext)
    if activity.step == .wake { moveVitality(towards: vitalityTarget, at: t) }
  }

  /// Another group much better than the one playing, once it has played its minimum.
  private mutating func preemption(at t: Double) -> CatActivityGroup? {
    let group = activity.step.group
    guard group != .react, t - activity.groupStart >= CatStatechart.minimumDwell(group) else {
      return nil
    }
    scores = CatUtility.scores(utilityInput(at: t))
    guard let current = scores.first(where: { $0.group == group })?.score,
      let best = scores.max(by: { $0.score < $1.score }), best.group != group,
      best.score > max(current, 1e-6) * CatUtility.hysteresis
    else { return nil }
    return best.group
  }

  private mutating func finishGroup(at t: Double) {
    let group = activity.step.group
    if let piece = activity.inspecting { inspected.insert(piece.id) }
    recent.append(CatEpisode(group: group, start: activity.groupStart, end: t))
    if recent.count > config.recentCount { recent.removeFirst(recent.count - config.recentCount) }
  }

  private mutating func choose(at t: Double, cause: CatTransitionCause) {
    if vitality == .asleep || life.asleep {
      enterRest(at: t, cause: life.asleep ? .vitality : cause)
      return
    }
    scores = CatUtility.scores(utilityInput(at: t))
    let group = CatUtility.choose(scores, roll: dice(t, 1))
    enter(group: group, at: t, cause: cause)
  }

  private mutating func enter(group: CatActivityGroup, at t: Double, cause: CatTransitionCause) {
    if group == .rest {
      enterRest(at: t, cause: cause)
      return
    }
    enter(script: chooseScript(group, at: t), at: t, cause: cause)
  }

  private mutating func enterRest(at t: Double, cause: CatTransitionCause) {
    let spot = chooseNapSpot(at: t)
    let kneads = dice(t, 3) < 0.3 + 0.5 * personality.cuddly
    var script: [CatActivityStep] =
      kneads ? [.findNapSpot, .knead, .curl, .wake] : [.findNapSpot, .curl, .wake]
    // A sleepy cat yawns first; an awake one on its way to a nap only now and then.
    let sleepy = vitality != .awake || life.pressure > config.drowsyAbove
    if vitality != .asleep, dice(t, 7) < (sleepy ? 0.85 : 0.25) { script.insert(.yawn, at: 0) }
    enter(script: script, at: t, cause: cause, napSpot: spot)
  }

  private mutating func enter(
    script: [CatActivityStep], at t: Double, cause: CatTransitionCause,
    napSpot: RoomAffordance.Kind? = nil
  ) {
    let before = stack
    if script.first == .sulk { snubbed = false }
    let inspecting = script.contains(.inspectFurniture) ? novelPiece(at: t) : nil
    activity = makeActivity(
      script: script, index: 0, at: t, groupStart: t, napSpot: napSpot ?? activity.napSpot,
      inspecting: inspecting)
    log(before, cause: cause)
  }

  private func makeActivity(
    script: [CatActivityStep], index: Int, at t: Double, groupStart: Double,
    napSpot: RoomAffordance.Kind?, inspecting: RoomAffordance? = nil
  ) -> Activity {
    let step = script[index]
    let length = BrainDice.range(CatStatechart.duration(step), dice(t, 2))
    let roll = dice(t, 4)
    return Activity(
      step: step, start: t, end: Self.quantize(t + length, config.decisionStep), script: script,
      index: index, groupStart: groupStart, napSpot: napSpot, inspecting: inspecting,
      target: CatStatechart.target(
        step, room: room, napSpot: napSpot, inspecting: inspecting?.kind, roll: roll),
      gaze: CatStatechart.gaze(step, roll: roll))
  }

  // MARK: - Vitality

  /// Where vitality is heading: asleep at night or curled up, drowsy when the pressure builds.
  private var vitalityTarget: CatVitality {
    if activity.step == .curl { return .asleep }
    if life.asleep { return .asleep }
    if life.pressure > config.drowsyAbove { return .drowsy }
    return .awake
  }

  private mutating func checkVitality() {
    let t = time
    moveVitality(towards: vitalityTarget, at: t)
    // Night came: the cat goes to curl up as soon as it is drowsy, whatever it was doing.
    if life.asleep, vitality != .awake, echo == nil, activity.step.group != .rest,
      activity.step.group != .react
    {
      finishGroup(at: t)
      enterRest(at: t, cause: .vitality)
    }
  }

  private mutating func moveVitality(towards target: CatVitality, at t: Double) {
    guard target != vitality, t - vitalitySince >= CatStatechart.vitalityDwell else { return }
    let next: CatVitality =
      switch (vitality, target) {
      case (.awake, _): .drowsy
      case (.asleep, _): .drowsy
      case (.drowsy, let target): target
      }
    moveVitality(to: next, at: t)
  }

  private mutating func moveVitality(to next: CatVitality, at t: Double) {
    guard next != vitality else { return }
    let before = stack
    vitality = next
    vitalitySince = t
    log(before, cause: .vitality)
  }

  // MARK: - Helpers

  func dice(_ t: Double, _ salt: UInt64) -> Double {
    BrainDice.roll(seed, t, salt)
  }

  static func quantize(_ t: Double, _ step: Double) -> Double {
    (t / step).rounded(.up) * step
  }

  private mutating func log(_ before: CatBrainStack, cause: CatTransitionCause) {
    let after = stack
    guard after != before else { return }
    transitions.append(CatBrainTransition(at: time, from: before, to: after, cause: cause))
    if transitions.count > config.transitionCount {
      transitions.removeFirst(transitions.count - config.transitionCount)
    }
  }
}
