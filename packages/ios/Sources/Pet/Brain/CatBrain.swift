import Foundation

/// The constants of the cat's brain.
public struct CatBrainConfig: Hashable, Sendable {
  /// Decisions land on a grid this fine, in seconds, so both phones decide at the same instants.
  public var decisionStep = 0.25
  /// How often vitality and the needs are looked at again between steps, in seconds.
  public var checkEvery = 15.0
  /// The local hour each day of the brain starts from its canonical state. The cat is asleep
  /// then on almost every day, so the fresh start does not show.
  public var dayStartHour = 4.0
  /// How many days before today a cold start folds, for what the cat remembers.
  public var memoryDays = 2.0
  /// Sleep pressure above this makes the cat drowsy. The pressure already counts how tired it is.
  public var drowsyAbove = 0.55
  /// How long a pet, a game or a meal from either phone holds the cat, in seconds.
  public var petEcho = 4.0
  public var feedEcho = 7.0
  /// Recent groups remembered for boredom.
  public var recentCount = 12
  /// Transitions kept, for the debug overlay; tests keep them all.
  public var transitionCount = 10

  public init() {}

  public static let standard = CatBrainConfig()

  /// A partner unseen for this long is missed: the cat watches the window and waits by the door.
  public static let missingAfterHours = 12.0
}

/// A few bits of randomness from the seed and the moment alone, with no state, so a decision at
/// the same instant comes out the same on every phone however the fold got there.
public enum BrainDice {
  public static func roll(_ seed: UInt64, _ time: Double, _ salt: UInt64) -> Double {
    let tick = UInt64(bitPattern: Int64((time * 4).rounded(.down)))
    var random = SplitMix64(
      seed: seed ^ (tick &* 0x9E37_79B9_7F4A_7C15) ^ (salt &* 0xD6E8_FEB8_6659_FD93))
    return Double(random.next() >> 11) / Double(1 << 53)
  }

  static func range(_ range: ClosedRange<Double>, _ roll: Double) -> Double {
    range.lowerBound + (range.upperBound - range.lowerBound) * roll
  }
}

/// What the cat's brain shows at one moment: its state stack and what the body should do.
public struct CatBrainFrame: Hashable, Sendable {
  public var stack: CatBrainStack
  /// The clip to play once the body is at `target`.
  public var action: CatAction
  public var target: CatTarget
  public var gaze: CatGaze
  /// How fast to travel, 0 walking to 1 running.
  public var pace: Double
  public var stepStart: Double
  public var stepEnd: Double
  /// Whether it would bat at a finger resting near the edge of the screen.
  public var eager: Bool

  public init(
    stack: CatBrainStack, action: CatAction, target: CatTarget, gaze: CatGaze, pace: Double,
    stepStart: Double, stepEnd: Double, eager: Bool = false
  ) {
    self.stack = stack
    self.action = action
    self.target = target
    self.gaze = gaze
    self.pace = pace
    self.stepStart = stepStart
    self.stepEnd = stepEnd
    self.eager = eager
  }

  /// The still picture a surface without a scene shows for this frame.
  public var pose: PetPose { stack.vitality == .asleep ? .sleeping : .proud }
}

/// The cat's brain: a hierarchical state machine with vitality, activity and interaction regions,
/// utility choosing the activity, and a seeded personality.
///
/// It is a pure function of the life events, the time and the seed. Every decision falls on a
/// fixed grid of absolute times and draws its randomness from ``BrainDice`` at that instant, so
/// the same events give the same cat on both phones and in the widget, with no server tick. A
/// fold advances only at decision times; between them `advance(to:)` is one comparison.
public struct CatBrain: Sendable {
  public let seed: UInt64
  public let config: CatBrainConfig
  /// The personality the cat was born with, from its seed.
  public let nature: CatPersonality
  /// Today's personality: the one it was born with, moved by the last few days.
  public private(set) var personality: CatPersonality
  /// Where it likes to rest, from yesterday and today.
  public private(set) var memory: CatMemory
  public private(set) var room: RoomAffordances
  public private(set) var weather: ViewWeather

  /// The last decision time processed, in seconds since 1970.
  public private(set) var time: Double
  public private(set) var vitality: CatVitality = .awake
  private var vitalitySince: Double
  private var activity: Activity
  private var echo: (interaction: CatInteraction, until: Double)?
  /// The activity as it was when an interaction broke in, to come back to afterwards.
  private var history: Activity?
  private var life: CatLifeSample
  private var focus: NeedFocus
  private var nextCheck: Double
  private var nextDay: Double
  private var pending: [LifeEvent] = []
  private var lastSeen: [String: Double] = [:]
  private var born: Double
  private var inspected = Set<String>()
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
    seed: UInt64, personality: CatPersonality? = nil, day: CatDay? = nil, room: RoomAffordances,
    weather: ViewWeather = .clear, start: Double, life: CatLifeSample, utcOffset: Int,
    lifeConfig: LifeConfig = .standard, config: CatBrainConfig = .standard
  ) {
    self.seed = seed
    self.config = config
    nature = personality ?? .seeded(seed)
    self.personality = day?.personality ?? nature
    memory = day?.memory ?? CatMemory()
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

  private let utcOffset: Int
  private let lifeConfig: LifeConfig

  // MARK: - Reading

  public var stack: CatBrainStack {
    CatBrainStack(vitality: vitality, step: activity.step, interaction: echo?.interaction)
  }

  /// The frame for the brain as it is, with `live` from this phone's own touch over it.
  public func frame(live: CatInteraction? = nil) -> CatBrainFrame {
    var interaction = echo?.interaction
    if let live, live.priority >= interaction?.priority ?? .min { interaction = live }
    var stack = stack
    stack.interaction = interaction
    let action =
      interaction.map { Self.clip($0, asleep: vitality == .asleep) }
      ?? CatStatechart.clip(activity.step)
    return CatBrainFrame(
      stack: stack, action: action, target: interaction == nil ? activity.target : .stay,
      gaze: interaction.map { _ in CatGaze.camera } ?? activity.gaze,
      pace: CatStatechart.pace(activity.step), stepStart: activity.start, stepEnd: activity.end,
      eager: eager)
  }

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

  /// Folds every decision up to `now` in order. Cheap when nothing is due.
  public mutating func advance(to now: Double, life sampler: inout CatLifeSampler) {
    while true {
      let next = nextDecision
      guard next <= now else { return }
      time = max(time, next)
      if nextDay <= time {
        nextDay = dayStart(after: time)
        let day = Self.opening(
          at: time, seed: seed, nature: nature, room: room, weather: weather, sampler: &sampler,
          utcOffset: utcOffset, config: config)
        personality = day.personality
        memory = day.memory
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
      if let spot = spot { memory.petted(at: spot) }
      interrupt(with: .petted(.back), for: config.petEcho, at: t)
    case .feed:
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
    echo = nil
    guard let history else { return }
    self.history = nil
    activity = history
    log(before, cause: .history)
    if activity.end <= time { stepEnded() }
  }

  // MARK: - Steps

  /// The kind of spot the cat is at, or headed for.
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
    let script: [CatActivityStep] =
      kneads ? [.findNapSpot, .knead, .curl, .wake] : [.findNapSpot, .curl, .wake]
    enter(script: script, at: t, cause: cause, napSpot: spot)
  }

  private mutating func enter(
    script: [CatActivityStep], at t: Double, cause: CatTransitionCause,
    napSpot: RoomAffordance.Kind? = nil
  ) {
    let before = stack
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

  /// One of the group's scripts, weighted by what the room has, the cat's traits and the hour.
  private func chooseScript(_ group: CatActivityGroup, at t: Double) -> [CatActivityStep] {
    let p = personality
    let away = awayHours(at: t) > CatBrainConfig.missingAfterHours
    let candidates: [([CatActivityStep], Double)] =
      switch group {
      case .idle:
        [
          ([.sit], 1), ([.loaf], 0.4 + p.lazy), ([.sit, .lookAround], 0.4 + p.curious),
          ([.lookAround, .sit], 0.3 + p.curious),
        ]
      case .explore:
        [
          ([.wander, .sniffObject], 1), ([.wander], 0.6),
          ([.inspectFurniture, .sniffObject], novelPiece(at: t) != nil ? 4 : 0),
        ]
      case .groom:
        [
          ([.groomPaw], 1), ([.groomPaw, .groomFlank], 1), ([.groomFlank, .groomTail], 0.7),
          ([.groomPaw, .groomFlank, .groomTail], 0.4 + p.lazy),
        ]
      case .eat: [([.walkToBowl, .eat, .lickLips], 1)]
      case .play:
        [
          ([.stalk, .pounce], 1), ([.stalk, .pounce, .chase], 0.4 + p.bold),
          ([.batObject], room.reachable(.toy) ? 0.8 : 0.3),
          ([.zoomies], 0.2 + p.playful * 0.8), ([.chase, .pounce], 0.5),
        ]
      case .watch: [([.watchWindow], 1), ([.watchPartnerWindow], away ? 1.5 : 0)]
      case .social:
        [
          ([.seekYou, .rub], 0.6 + p.cuddly), ([.slowBlink], 0.8),
          ([.seekYou, .slowBlink], 0.4 + p.vocal),
          ([.bringToy], room.reachable(.toy) ? 0.3 + p.playful * 0.5 : 0),
          ([.waitByDoor], away ? 1.2 : 0),
        ]
      case .mischief:
        [
          ([.pushItem], room.reachable(.smallItem) ? 0.5 + p.bold : 0),
          ([.sitInCardigan], room.reachable(.soft) ? 0.6 + p.cuddly : 0),
          ([.sitOnDesk], room.reachable(.desk) ? 0.6 + p.bold : 0),
        ]
      case .rest: [([.findNapSpot, .curl, .wake], 1)]
      case .react: [([.curiousTilt], 1)]
      }
    let open = candidates.filter { $0.1 > 0 }
    let total = open.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return [.sit] }
    var left = dice(t, 5) * total
    for (script, weight) in open {
      left -= weight
      if left < 0 { return script }
    }
    return open.last?.0 ?? [.sit]
  }

  /// Where to curl up: a bed or something soft, the sun by day, the rug, else its own place.
  /// A spot it has rested and been petted in a lot is up to four times likelier.
  private func chooseNapSpot(at t: Double) -> RoomAffordance.Kind? {
    let options = napSpots(at: t).map { kind, weight in
      (kind, weight * (1 + 3 * memory.fondness(kind)))
    }
    let total = options.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return nil }
    var left = dice(t, 6) * total
    for (kind, weight) in options {
      left -= weight
      if left < 0 { return kind }
    }
    return options.last?.0
  }

  /// The places the cat can curl up in now, weighted by its traits.
  private func napSpots(at t: Double) -> [(RoomAffordance.Kind, Double)] {
    let sunny = isSunny(at: t)
    let options: [(RoomAffordance.Kind, Double)] = [
      (.bed, 3), (.soft, 2 + personality.cuddly), (.sunbeam, sunny ? 3 : 0), (.rug, 1),
      (.box, 1 + personality.curious), (.shelf, personality.bold * 1.5),
    ]
    return options.filter { kind, weight in
      weight > 0 && (kind == .sunbeam ? sunny && room.reachable(.window) : room.reachable(kind))
    }
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

  // MARK: - Utility

  public func utilityInput(at t: Double) -> CatUtilityInput {
    CatUtilityInput(
      now: t, needs: life.needs, focus: focus.focus, mood: life.mood, hour: hour(at: t),
      vitality: vitality, sleepy: life.pressure > config.drowsyAbove, personality: personality,
      room: effectiveRoom(at: t), weather: weather,
      recent: recent, awayHours: awayHours(at: t), hasNovelty: novelPiece(at: t) != nil,
      spotFondness: napSpots(at: t).map { memory.fondness($0.0) }.max() ?? 0)
  }

  /// How long a piece counts as new after it appears, in seconds.
  public static let noveltySeconds = 24.0 * 3600

  /// A piece put in the room within the last day that the cat has not been to look at yet.
  private func novelPiece(at t: Double) -> RoomAffordance? {
    room.furniture.first { piece in
      guard let since = piece.since, t >= since, t - since < Self.noveltySeconds else {
        return false
      }
      return !inspected.contains(piece.id)
    }
  }

  /// The room with a sunbeam under the window by day in clear weather.
  private func effectiveRoom(at t: Double) -> RoomAffordances {
    guard isSunny(at: t), room.has(.window), !room.has(.sunbeam) else { return room }
    let window = room.all.first { $0.kind == .window }
    return RoomAffordances(
      room.all + [
        RoomAffordance(id: "sunbeam", kind: .sunbeam, reachable: window?.reachable ?? false)
      ])
  }

  private func isSunny(at t: Double) -> Bool {
    let hour = hour(at: t)
    return weather == .clear && hour >= 9 && hour < 17
  }

  /// Who did something for the cat last, of the events folded so far.
  public var lastBy: String? {
    lastSeen.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
  }

  /// How long the partner seen least recently has been away. With only one partner seen yet,
  /// nobody is missed.
  public func awayHours(at t: Double) -> Double {
    guard lastSeen.count >= 2, let oldest = lastSeen.values.min() else { return 0 }
    return max(t - oldest, 0) / 3600
  }

  // MARK: - Helpers

  private func dice(_ t: Double, _ salt: UInt64) -> Double {
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
