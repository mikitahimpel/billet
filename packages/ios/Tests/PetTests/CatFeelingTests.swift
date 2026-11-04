import Foundation
import Testing

@testable import Pet

@Suite("CatFeeling")
struct CatFeelingTests {
  typealias Day = CatBrainTests

  // MARK: - From the needs

  @Test func eachFeelingComesFromItsNeed() {
    func feel(_ needs: PetNeeds, mood: Double = 0.5, asleep: Bool = false, sleepy: Bool = false)
      -> CatFeeling
    {
      CatFeeling.of(needs: needs, mood: mood, asleep: asleep, sleepy: sleepy, temperament: nil)
    }
    let fine = PetNeeds(all: 0.7)
    #expect(feel(fine, asleep: true) == .asleep)
    #expect(feel(PetNeeds(full: 0.21, rested: 0.7, loved: 0.7, playful: 0.7)) == .hangry)
    #expect(feel(PetNeeds(full: 0.33, rested: 0.7, loved: 0.7, playful: 0.7)) == .hungry)
    #expect(feel(PetNeeds(full: 0.7, rested: 0.7, loved: 0.3, playful: 0.3)) == .lonely)
    #expect(feel(PetNeeds(full: 0.7, rested: 0.7, loved: 0.7, playful: 0.3)) == .bored)
    #expect(feel(fine, sleepy: true) == .sleepy)
    #expect(feel(PetNeeds(full: 0.7, rested: 0.3, loved: 0.7, playful: 0.7)) == .sleepy)
    #expect(feel(PetNeeds(all: 0.9), mood: 0.9) == .happy)
    #expect(feel(fine, mood: 0.6) == .content)
    // Hunger comes first: a hungry cat is not sulking about it.
    #expect(feel(PetNeeds(full: 0.3, rested: 0.7, loved: 0.3, playful: 0.3)) == .hungry)
  }

  @Test func aDivaOverreactsAndASleepyheadUnderreacts() {
    let full = 0.29
    func feel(_ type: CatTemperament?) -> CatFeeling {
      CatFeeling.of(
        needs: PetNeeds(full: full, rested: 0.7, loved: 0.7, playful: 0.7), mood: 0.5,
        asleep: false, sleepy: false, temperament: type)
    }
    #expect(feel(.diva) == .hangry)
    #expect(feel(nil) == .hungry)
    #expect(feel(.sleepyhead) == .hungry)
    #expect(
      CatFeeling.hunger(0.25, temperament: .diva) > CatFeeling.hunger(0.25, temperament: nil))
    #expect(
      CatFeeling.hunger(0.25, temperament: .sleepyhead) < CatFeeling.hunger(0.25, temperament: nil))
    // Not hungry at all is no hunger, whatever the drama.
    for type in CatTemperament.allCases {
      #expect(CatFeeling.hunger(0.5, temperament: type) == 0)
    }
  }

  @Test(arguments: CatFeeling.allCases)
  func everyFeelingSaysSomething(_ feeling: CatFeeling) {
    #expect(!feeling.words.isEmpty)
    #expect(!feeling.wants.isEmpty)
  }

  // MARK: - Acted out

  /// `count` events of `kind`, `every` hours apart from `from`, by `a` and `b` in turn from
  /// `first`.
  static func series(
    _ kind: LifeEvent.Kind, _ count: Int, from: Double, every: Double, first: String = "a",
    _ n: Int
  ) -> [LifeEvent] {
    let second = first == "a" ? "b" : "a"
    var out: [LifeEvent] = []
    for index in 0..<count {
      let by = index % 2 == 0 ? first : second
      out.append(Day.event(kind, by, from + Double(index) * every, n))
    }
    return out
  }

  /// Fed two days ago and never since, but petted and played with: hangry all day.
  static let starving: [LifeEvent] = {
    var events = [Day.event(.feed, "a", -50)]
    events += series(.pet, 12, from: -20, every: 3, 1)
    events += series(.note, 6, from: -18, every: 6, first: "b", 2)
    events += series(.play, 6, from: -10, every: 5, first: "a", 3).map {
      LifeEvent(id: $0.id, kind: $0.kind, by: "a", at: $0.at)
    }
    return events
  }()

  /// Fed every three hours, petted, written to and played with: never hungry.
  static let wellFed: [LifeEvent] = {
    var events = series(.feed, 16, from: -24, every: 3, 4)
    events += series(.pet, 16, from: -23, every: 3, first: "b", 5)
    events += series(.note, 8, from: -22, every: 6, 6)
    events += series(.play, 8, from: -21, every: 6, first: "b", 7)
    return events
  }()

  /// Fed and played with, but nobody has petted it or written for days.
  static let unloved: [LifeEvent] = {
    var events = series(.feed, 24, from: -48, every: 3, 8).map {
      LifeEvent(id: $0.id, kind: $0.kind, by: "a", at: $0.at)
    }
    events += series(.play, 12, from: -46, every: 6, 9).map {
      LifeEvent(id: $0.id, kind: $0.kind, by: "a", at: $0.at)
    }
    return events
  }()

  static let tantrum: Set<CatActivityStep> = [.yowl, .knockOff, .flop]
  static let asking: Set<CatActivityStep> = [.waitByBowl, .pawBowl, .beg]

  @Test func aHangryCatThrowsTantrumsAndAFedOneNever() {
    let starving = Self.day(Self.starving)
    let fed = Self.day(Self.wellFed)
    #expect(starving.allSatisfy { $0.1.feeling == .hangry || $0.1.feeling == .asleep })
    let stacks: [(Double, CatBrainStack)] = starving.map { ($0.0, $0.1.stack) }
    let raging = Day.share(stacks) { Self.tantrum.contains($0.step) }
    let needy = Day.share(stacks) {
      Self.tantrum.contains($0.step) || Self.asking.contains($0.step)
    }
    #expect(raging > 0.04)
    #expect(needy > 0.08)
    #expect(fed.allSatisfy { !Self.tantrum.contains($0.1.stack.step) })
    // An empty bowl is never eaten from.
    #expect(starving.allSatisfy { $0.1.stack.step != .eat })
  }

  @Test func aTantrumYowlsAndMeows() {
    let frames = Self.day(Self.starving).map(\.1)
    let voices = Set(frames.compactMap(\.voice))
    #expect(voices.isSuperset(of: [.meow, .yowl]))
    for frame in frames where frame.stack.step == .yowl && frame.stack.interaction == nil {
      #expect(frame.voice == .yowl)
    }
  }

  @Test func aMealEndsTheTantrumAtOnce() throws {
    // A tantrum step still under way five seconds on, with nobody touching the cat.
    let day = Self.day(Self.starving)
    let start = try #require(
      zip(day, day.dropFirst()).first { now, next in
        Self.tantrum.contains(now.1.stack.step) && now.1.stack.interaction == nil
          && next.1.stepStart == now.1.stepStart
      }?.0.0)
    let feed = Day.event(.feed, "b", (start - Day.midnight) / 3600 + 1 / 3600.0, 10)
    let after = CatBrainRunner.replay(
      events: Self.starving + [feed], now: start + 2, context: Day.context, seed: 7,
      personality: .even, room: Day.room)
    #expect(after.stack.step == .walkToBowl)
    #expect(after.stack.interaction == .fed)
    #expect(after.feeling != .hangry && after.feeling != .hungry)
    let later = CatBrainRunner.replay(
      events: Self.starving + [feed], now: start + 120, context: Day.context, seed: 7,
      personality: .even, room: Day.room)
    #expect(!Self.tantrum.contains(later.stack.step))
  }

  @Test func aHungryCatBegsAtAFinger() throws {
    let start = try #require(
      Self.day(Self.starving).first {
        $0.1.stack.vitality == .awake && $0.1.stack.interaction == nil
      }?.0)
    let brain = CatBrainRunner.replay(
      events: Self.starving, now: start, context: Day.context, seed: 7, personality: .even,
      room: Day.room)
    #expect(brain.frame(live: .followFinger).action == .wave)
  }

  @Test func aLonelyCatSulksIgnoresTheFirstPetAndForgivesTheSecond() throws {
    let day = Self.day(Self.unloved)
    let start = try #require(
      zip(day, day.dropFirst()).first { $0.1.stack.step != .sulk && $1.1.stack.step == .sulk }?.1.0
    )
    let brain = CatBrainRunner.replay(
      events: Self.unloved, now: start, context: Day.context, seed: 7, personality: .even,
      room: Day.room)
    // A finger on it changes nothing yet.
    #expect(brain.frame(live: .petted(.back)).stack.interaction == nil)
    #expect(brain.frame(live: .petted(.back)).action == CatStatechart.clip(.sulk))
    let hour = (start - Day.midnight) / 3600
    let first = Day.event(.pet, "a", hour + 2 / 3600.0, 11)
    let second = Day.event(.pet, "b", hour + 6 / 3600.0, 12)
    let snubbed = CatBrainRunner.replay(
      events: Self.unloved + [first, second], now: start + 4, context: Day.context, seed: 7,
      personality: .even, room: Day.room)
    #expect(snubbed.stack.step == .sulk)
    #expect(snubbed.stack.interaction == nil)
    let forgiven = CatBrainRunner.replay(
      events: Self.unloved + [first, second], now: start + 7, context: Day.context, seed: 7,
      personality: .even, room: Day.room)
    #expect(forgiven.stack.step == .seekYou || forgiven.stack.step == .rub)
  }

  @Test func aSleepyCatYawnsBeforeItCurlsUp() {
    let brain = Day.fold(Day.bothActive, to: 30)
    let yawns = brain.transitions.filter { $0.to.step == .yawn }
    #expect(!yawns.isEmpty)
    for yawn in yawns {
      #expect(CatStatechart.successors(.yawn).contains(.findNapSpot))
      #expect(yawn.to.group == .rest)
    }
  }

  @Test func aHappyCatPurrs() {
    let day = Self.day(Self.wellFed)
    #expect(day.contains { $0.1.purring })
    #expect(day.allSatisfy { !$0.1.purring || $0.1.stack.vitality != .asleep })
  }

  static let types: [CatTemperament?] = [nil, .cuddler, .explorer, .diva, .sleepyhead, .clown]

  @Test(arguments: types)
  func everyMoveOfANeedyDayIsLegal(_ type: CatTemperament?) {
    for events in [Self.starving, Self.unloved] {
      var illegal: [CatBrainTransition] = []
      // A day start puts the cat back in its canonical state, whatever it was doing.
      for transition in Self.fold(events, type, to: 22).transitions
      where transition.cause != .dayStart {
        let activityOK =
          transition.from.step == transition.to.step
          || CatStatechart.isLegal(
            from: transition.from.step, to: transition.to.step, cause: transition.cause)
        let vitalityOK = CatStatechart.isLegal(
          from: transition.from.vitality, to: transition.to.vitality)
        if !activityOK || !vitalityOK { illegal.append(transition) }
      }
      #expect(illegal.isEmpty, "\(String(describing: type)): \(illegal.prefix(3))")
    }
  }

  @Test(arguments: [CatTemperament.diva, .sleepyhead])
  func aFreshReplayOfATantrumEqualsALongRun(_ type: CatTemperament) {
    var long = CatBrainRunner(
      events: Self.starving, now: Day.at(8), context: Day.context, seed: 3, temperament: type,
      room: Day.room)
    var t = Day.at(8)
    while t < Day.at(12) {
      long.advance(to: t)
      t += 37
    }
    let fresh = CatBrainRunner.replay(
      events: Self.starving, now: t, context: Day.context, seed: 3, temperament: type,
      room: Day.room)
    long.advance(to: t)
    #expect(fresh.frame() == long.brain.frame())
  }

  @Test func aDivaRagesMoreThanASleepyhead() {
    // Half a day without food: a Diva is hangry, a Sleepyhead only peckish.
    let events = [Day.event(.feed, "a", 0)] + Self.wellFed.filter { $0.kind != .feed }
    func rage(_ type: CatTemperament) -> Double {
      var runner = CatBrainRunner(
        events: events, now: Day.at(9), context: Day.context, seed: 5, temperament: type,
        room: Day.room)
      var count = 0
      var raging = 0
      var t = Day.at(9)
      while t < Day.at(21) {
        runner.advance(to: t)
        if runner.frame.feeling == .hangry { raging += 1 }
        count += 1
        t += 30
      }
      return Double(raging) / Double(count)
    }
    #expect(rage(.diva) > rage(.sleepyhead) + 0.2)
  }

  // MARK: - Decay

  /// A couple who feed it twice a day, pet it a few times, write once and play once.
  static let couple: [LifeEvent] = {
    var events: [LifeEvent] = []
    for day in -3...1 {
      let o = Double(day) * 24
      events.append(Day.event(.feed, "a", o + 8, 20))
      events.append(Day.event(.pet, "a", o + 8.5, 21))
      events.append(Day.event(.note, "b", o + 12.5, 22))
      events.append(Day.event(.feed, "b", o + 19, 23))
      events.append(Day.event(.play, "b", o + 20, 24))
      events.append(Day.event(.pet, "b", o + 21.5, 25))
      events.append(Day.event(.pet, "a", o + 22, 26))
    }
    return events
  }()

  @Test func aNormalCoupleSeesEachNeedWithinADay() {
    var seen = Set<CatFeeling>()
    var t = Day.at(0)
    let context = LifeContext(
      partners: ["a", "b"], utcOffset: 0,
      born: Date(timeIntervalSince1970: Day.midnight - 3 * 86400))
    while t < Day.at(24) {
      let state = PetLife.state(
        events: Self.couple, now: Date(timeIntervalSince1970: t), context: context)
      for need in PetNeed.allCases {
        #expect(state.needs[need] >= LifeConfig.standard.floor - 1e-9)
      }
      seen.insert(
        CatFeeling.of(
          needs: state.needs, mood: state.mood, asleep: state.asleep, sleepy: false,
          temperament: nil))
      t += 900
    }
    #expect(seen.isSuperset(of: [.hungry, .lonely, .bored, .asleep]), "\(seen)")
  }

  @Test func oneCareBringsItBackFromTheFloor() {
    let config = LifeConfig.standard
    let floor = config.floor
    #expect(PetLife.gain(floor, by: config.feedGain, returns: config.returns) > config.lowUntil)
    #expect(PetLife.gain(floor, by: config.playGain, returns: config.returns) > config.lowBelow)
    // A note warms it towards both of you at once.
    #expect(PetLife.gain(floor, by: config.noteGain, returns: config.returns) > config.lowBelow)
  }

  // MARK: - Nudges

  static func nudge(_ events: [LifeEvent], at hour: Double, sent: [Date] = [])
    -> CatNudge.Plan?
  {
    CatNudge.next(
      events: events, now: Date(timeIntervalSince1970: Day.at(hour)), context: Day.context,
      temperament: nil, name: "Mochi", sent: sent)
  }

  @Test func aHungryCatIsNudgedOutsideQuietHours() throws {
    let plan = try #require(Self.nudge(Self.starving, at: 6))
    #expect(plan.feeling == .hangry)
    #expect(plan.body.contains("Mochi"))
    #expect(!CatNudge.isQuiet(plan.at.timeIntervalSince1970, utcOffset: 0))
    #expect(plan.at.timeIntervalSince1970 >= Day.at(8.5))
  }

  @Test func careFromEitherPartnerMovesTheNudge() throws {
    let before = try #require(Self.nudge(Self.starving, at: 9))
    // The partner feeds it: the cat is fine for hours.
    let fed = Self.starving + [Day.event(.feed, "b", 9, 30)]
    let after = Self.nudge(fed, at: 9)
    #expect(after.map { $0.at > before.at.addingTimeInterval(3 * 3600) } ?? true)
  }

  @Test func atMostTwoADayAndHoursApart() throws {
    let morning = Date(timeIntervalSince1970: Day.at(9))
    let noon = Date(timeIntervalSince1970: Day.at(13.5))
    let afternoon = try #require(Self.nudge(Self.starving, at: 10, sent: [morning]))
    #expect(afternoon.at.timeIntervalSince(morning) >= CatNudge.apart)
    let tomorrow = try #require(Self.nudge(Self.starving, at: 14, sent: [morning, noon]))
    #expect(tomorrow.at.timeIntervalSince1970 >= Day.at(24 + CatNudge.quietUntil))
  }

  @Test func aWellCaredForCatIsNotNudged() {
    #expect(Self.nudge(Self.wellFed, at: 9)?.at.timeIntervalSince1970 ?? .infinity > Day.at(21))
  }

  // MARK: - Helpers

  /// The frame every five seconds from 9 a.m. to 8 p.m.
  static func day(_ events: [LifeEvent], seed: UInt64 = 7) -> [(Double, CatBrainFrame)] {
    var runner = CatBrainRunner(
      events: events, now: Day.at(9), context: Day.context, seed: seed, personality: .even,
      room: Day.room)
    var out: [(Double, CatBrainFrame)] = []
    var t = Day.at(9)
    while t < Day.at(20) {
      runner.advance(to: t)
      out.append((t, runner.frame))
      t += 5
    }
    return out
  }

  static func fold(_ events: [LifeEvent], _ type: CatTemperament?, to hour: Double) -> CatBrain {
    let start = Day.at(-20)
    var sampler = CatLifeSampler(events: events, context: Day.context)
    var config = CatBrainConfig()
    config.transitionCount = .max
    var brain = CatBrain(
      seed: 7, temperament: type, room: Day.room, start: start, life: sampler.sample(at: start),
      utcOffset: 0, config: config)
    brain.remember(events.filter { $0.at.timeIntervalSince1970 < start })
    brain.schedule(events)
    brain.advance(to: Day.at(hour), life: &sampler)
    return brain
  }
}
