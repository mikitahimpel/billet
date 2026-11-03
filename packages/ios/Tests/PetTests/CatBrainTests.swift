import Foundation
import Testing

@testable import Pet

@Suite("CatBrain")
struct CatBrainTests {
  /// Midnight UTC on a Monday; the pair lives at UTC.
  static let midnight = 1_793_664_000.0
  static let context = LifeContext(
    partners: ["a", "b"], utcOffset: 0,
    born: Date(timeIntervalSince1970: midnight - 3 * 86400))
  static let room = RoomAffordances([
    RoomAffordance(id: "window", kind: .window),
    RoomAffordance(id: "bowl", kind: .bowl),
    RoomAffordance(id: "cardigan", kind: .soft),
    RoomAffordance(id: "mugs", kind: .smallItem),
    RoomAffordance(id: "yarn", kind: .toy),
    RoomAffordance(id: "cat-bed", kind: .bed, reachable: false),
  ])

  static func at(_ hour: Double) -> Double { midnight + hour * 3600 }

  static func event(_ kind: LifeEvent.Kind, _ by: String, _ hour: Double, _ n: Int = 0) -> LifeEvent
  {
    // Fixed IDs, so the same script gives the same events on every run.
    let id = UUID(uuidString: String(format: "00000000-0000-0000-%04X-%012X", n, Int(hour * 3600)))!
    return LifeEvent(id: id, kind: kind, by: by, at: Date(timeIntervalSince1970: at(hour)))
  }

  // MARK: - Scripted days

  /// Both partners about all day: notes, pets and a meal from each, a game at dusk.
  static let bothActive: [LifeEvent] = [
    event(.feed, "a", -40), event(.pet, "b", -30), event(.note, "a", -20), event(.pet, "a", -6),
    event(.pet, "b", -4), event(.note, "a", -2), event(.note, "b", -1),
    event(.feed, "a", 8), event(.note, "b", 8.5), event(.pet, "a", 9), event(.note, "a", 12.2),
    event(.pet, "b", 13), event(.feed, "b", 18), event(.play, "a", 19), event(.play, "b", 19.3),
    event(.note, "b", 21), event(.pet, "a", 22),
  ]

  /// Only `a` is about; `b` was last seen two days ago.
  static let partnerAway: [LifeEvent] = [
    event(.pet, "b", -48), event(.feed, "a", -30), event(.note, "a", -10),
    event(.feed, "a", 8), event(.pet, "a", 9), event(.note, "a", 12), event(.feed, "a", 18),
    event(.pet, "a", 21),
  ]

  /// The pair only writes notes.
  static let onlyNotes: [LifeEvent] =
    (0..<8).map { event(.note, $0 % 2 == 0 ? "a" : "b", 8 + Double($0) * 1.7) }
    + [event(.note, "a", -30), event(.note, "b", -20)]

  /// A game every half hour through the afternoon and evening.
  static let lotsOfPlay: [LifeEvent] =
    [event(.feed, "a", -30), event(.pet, "b", -20), event(.feed, "b", 8)]
    + (0..<16).map { event(.play, $0 % 2 == 0 ? "a" : "b", 12 + Double($0) * 0.5) }

  /// The stack every five seconds over `hours` from `from`.
  static func day(
    _ events: [LifeEvent], from: Double = 0, hours: Double = 24, seed: UInt64 = 7,
    personality: CatPersonality? = .even, room: RoomAffordances = room
  ) -> [(Double, CatBrainStack)] {
    var runner = CatBrainRunner(
      events: events, now: at(from), context: context, seed: seed, personality: personality,
      room: room)
    var out: [(Double, CatBrainStack)] = []
    var t = at(from)
    while t < at(from + hours) {
      runner.advance(to: t)
      out.append((t, runner.frame.stack))
      t += 5
    }
    return out
  }

  static func share(_ day: [(Double, CatBrainStack)], _ test: (CatBrainStack) -> Bool) -> Double {
    Double(day.filter { test($0.1) }.count) / Double(max(day.count, 1))
  }

  @Test func sleepsAtNightAndIsUpByDay() {
    let day = Self.day(Self.bothActive)
    let night = day.filter { Self.hour($0.0) >= 1 && Self.hour($0.0) < 5 }
    let afternoon = day.filter { Self.hour($0.0) >= 15 && Self.hour($0.0) < 18 }
    #expect(Self.share(night) { $0.vitality == .asleep } > 0.8)
    #expect(Self.share(afternoon) { $0.vitality != .asleep } > 0.5)
    // A busy day shows most of the repertoire.
    let groups = Set(day.map(\.1.group))
    #expect(groups.isSuperset(of: [.idle, .rest, .groom, .watch, .social, .react]))
  }

  @Test func aMissingPartnerIsWaitedFor() {
    let away = Self.day(Self.partnerAway, from: 7, hours: 14)
    let both = Self.day(Self.bothActive, from: 7, hours: 14)
    let waiting: (CatBrainStack) -> Bool = {
      $0.step == .waitByDoor || $0.step == .watchPartnerWindow
    }
    #expect(Self.share(away, waiting) > 0.02)
    #expect(Self.share(both, waiting) == 0)
  }

  @Test func eachNoteGetsALook() {
    let brain = Self.fold(Self.onlyNotes, to: 24)
    let tilts = brain.transitions.filter {
      $0.to.step == .curiousTilt && $0.from.step != .curiousTilt && $0.at >= Self.at(0)
    }
    #expect(tilts.count == 8)
  }

  @Test func everyGameIsPlayedAndTiresTheCat() {
    let brain = Self.fold(Self.lotsOfPlay, to: 21)
    let games = Self.lotsOfPlay.filter { $0.kind == .play }
    for game in games {
      let at = game.at.timeIntervalSince1970
      let answer = brain.transitions.first { $0.at == at && $0.cause == .event }
      #expect(answer?.to.step == .stalk || answer?.to.step == .wake, "game at \(Self.hour(at))")
    }
    // The needs engine tires the cat with each game: it rests more than on a day of notes.
    let busy = Self.day(Self.lotsOfPlay, from: 14, hours: 6)
    let quiet = Self.day(Self.onlyNotes, from: 14, hours: 6)
    let resting: (CatBrainStack) -> Bool = { $0.group == .rest }
    #expect(Self.share(busy, resting) > Self.share(quiet, resting))
  }

  // MARK: - Legality, dwell and history

  @Test(arguments: [bothActive, partnerAway, onlyNotes, lotsOfPlay])
  func everyTransitionIsLegal(_ events: [LifeEvent]) {
    var illegal: [CatBrainTransition] = []
    for transition in Self.fold(events, to: 30).transitions {
      let activityOK =
        transition.from.step == transition.to.step
        || CatStatechart.isLegal(
          from: transition.from.step, to: transition.to.step, cause: transition.cause)
      let vitalityOK = CatStatechart.isLegal(
        from: transition.from.vitality, to: transition.to.vitality)
      if !activityOK || !vitalityOK { illegal.append(transition) }
    }
    #expect(illegal.isEmpty, "\(illegal.prefix(3))")
  }

  @Test func noFlicker() {
    let transitions = Self.fold(Self.bothActive, to: 24).transitions
    // Vitality never moves again within its dwell, unless an event moved it.
    let vitality = transitions.filter {
      $0.from.vitality != $0.to.vitality && $0.cause == .vitality
    }
    for (a, b) in zip(vitality, vitality.dropFirst()) {
      #expect(b.at - a.at >= CatStatechart.vitalityDwell - 1e-9)
    }
    // No preemption cuts a group short of its minimum, and nothing bounces A → B → A in 3 s.
    var groupStart = Self.at(0)
    var lastGroup = CatActivityGroup.idle
    for transition in transitions where transition.from.group != transition.to.group {
      if transition.cause == .preempted {
        #expect(transition.at - groupStart >= CatStatechart.minimumDwell(lastGroup) - 1e-9)
      }
      groupStart = transition.at
      lastGroup = transition.to.group
    }
    let changes = transitions.filter { $0.from.step != $0.to.step }
    for (a, b) in zip(changes, changes.dropFirst())
    where a.cause != .interaction && b.cause != .history {
      #expect(!(b.to.step == a.from.step && b.at - a.at < 1), "\(a) then \(b)")
    }
  }

  @Test func aNapResumesAfterABriefPet() throws {
    // Folded to 2 a.m., deep asleep; a pet comes at 2:00:30.
    let pet = Self.event(.pet, "a", 2 + 30 / 3600.0)
    var brain = CatBrainRunner.replay(
      events: Self.bothActive, now: Self.at(2), context: Self.context, seed: 7, personality: .even,
      room: Self.room)
    #expect(brain.stack.step == .curl)
    let napEnd = brain.frame().stepEnd
    var sampler = CatLifeSampler(events: Self.bothActive + [pet], context: Self.context)
    brain.schedule([pet])
    brain.advance(to: Self.at(2) + 31, life: &sampler)
    #expect(brain.stack.interaction == .petted(.back))
    #expect(brain.stack.vitality == .asleep)
    #expect(brain.frame().action == .sleep)
    brain.advance(to: Self.at(2) + 30 + CatBrainConfig.standard.petEcho + 1, life: &sampler)
    #expect(brain.stack.interaction == nil)
    #expect(brain.stack.step == .curl)
    #expect(brain.frame().stepEnd >= napEnd)
    #expect(brain.transitions.last?.cause == .history)
  }

  @Test func liveTouchNeverChangesTheFold() {
    var touched = CatBrainRunner(
      events: Self.bothActive, now: Self.at(10), context: Self.context, seed: 7, room: Self.room)
    var plain = touched
    var t = Self.at(10)
    while t < Self.at(11) {
      touched.live = Int(t) % 60 < 20 ? .petted(.head) : nil
      touched.advance(to: t)
      plain.advance(to: t)
      #expect(touched.brain.stack == plain.brain.stack)
      if touched.live != nil { #expect(touched.frame.stack.interaction == .petted(.head)) }
      t += 3
    }
  }

  // MARK: - Two phones

  @Test func twoPhonesAgree() {
    let events = Self.bothActive
    // Phone A hears each event at once; phone B hears the partner's events 40 s late, and its own
    // at once. A ticks every frame for a while, B every few seconds.
    var a = CatBrainRunner(
      events: events.filter { $0.at.timeIntervalSince1970 < Self.at(7) }, now: Self.at(7),
      context: Self.context, seed: 99, room: Self.room)
    var b = a
    var t = Self.at(7)
    var compared = 0
    while t < Self.at(23) {
      let due = events.filter {
        let at = $0.at.timeIntervalSince1970
        return at >= Self.at(7) && at <= t
      }
      a.receive(due, now: t)
      b.receive(due.filter { $0.by == "b" || $0.at.timeIntervalSince1970 + 40 <= t }, now: t)
      a.advance(to: t)
      b.advance(to: t)
      let settled = events.allSatisfy {
        let at = $0.at.timeIntervalSince1970
        return at > t || at + 40 <= t
      }
      if settled {
        #expect(a.brain.stack == b.brain.stack, "at hour \(Self.hour(t))")
        compared += 1
      }
      t += Double(Int(t) % 7 == 0 ? 1 : 4)
    }
    #expect(compared > 1000)
    a.advance(to: t)
    let fresh = CatBrainRunner.replay(
      events: events, now: t, context: Self.context, seed: 99, room: Self.room)
    #expect(fresh.stack == a.brain.stack)
    #expect(fresh.frame() == a.brain.frame())
  }

  @Test func aFreshReplayEqualsALongRun() {
    // One phone has run since two days ago; the other opens the app now.
    let events = Self.bothActive
    var long = CatBrainRunner(
      events: events, now: Self.at(-30), context: Self.context, seed: 3, room: Self.room)
    var t = Self.at(-30)
    while t < Self.at(20) {
      long.advance(to: t)
      t += 37
    }
    let fresh = CatBrainRunner.replay(
      events: events, now: t, context: Self.context, seed: 3, room: Self.room)
    long.advance(to: t)
    #expect(fresh.frame() == long.brain.frame())
    #expect(fresh.personality == long.brain.personality)
    #expect(fresh.memory == long.brain.memory)
    #expect(!fresh.memory.spots.isEmpty)
  }

  // MARK: - Memory and drift

  static let napRoom = RoomAffordances([
    RoomAffordance(id: "window", kind: .window),
    RoomAffordance(id: "cardigan", kind: .soft),
    RoomAffordance(id: "rug", kind: .rug),
    RoomAffordance(id: "cat-bed", kind: .bed),
  ])

  @Test func aDayBeginsWithYesterdaysSpots() throws {
    var sampler = CatLifeSampler(events: Self.bothActive, context: Self.context)
    let line = CatBrain.dayStart(before: Self.at(12), utcOffset: 0, config: .standard)
    let day = CatBrain.opening(
      at: line, seed: 5, nature: .even, room: Self.napRoom, weather: .clear, sampler: &sampler,
      utcOffset: 0, config: .standard)
    let favourite = try #require(day.memory.favourite)
    #expect([.bed, .soft, .rug, .sunbeam].contains(favourite))
    let total = RoomAffordance.Kind.allCases.map { day.memory.fondness($0) }.reduce(0, +)
    #expect(abs(total - 1) < 1e-9)
    // Before the cat was born there is nothing to remember.
    let first = try #require(Self.context.born).timeIntervalSince1970
    let newborn = CatBrain.opening(
      at: first, seed: 5, nature: .even, room: Self.napRoom, weather: .clear, sampler: &sampler,
      utcOffset: 0, config: .standard)
    #expect(newborn.memory.spots.isEmpty)
  }

  @Test func aFavouriteSpotIsWhereItNaps() {
    // The same cat, once fond of the cardigan and once of the rug, naps where it likes.
    func naps(fondOf kind: RoomAffordance.Kind) -> [RoomAffordance.Kind: Int] {
      var memory = CatMemory()
      memory.rested(at: kind, seconds: 6 * 3600)
      var counts: [RoomAffordance.Kind: Int] = [:]
      for seed in UInt64(1)...6 {
        var sampler = CatLifeSampler(events: Self.lotsOfPlay, context: Self.context)
        let start = Self.at(4)
        var brain = CatBrain(
          seed: seed, personality: .even, day: CatDay(personality: .even, memory: memory),
          room: Self.napRoom, start: start, life: sampler.sample(at: start), utcOffset: 0)
        brain.schedule(sampler.events(after: start, through: .infinity))
        var t = start
        var last: CatTarget?
        while t < Self.at(23) {
          brain.advance(to: t, life: &sampler)
          let frame = brain.frame()
          if frame.stack.step == .curl, frame.target != last,
            case .affordance(let spot) =
              frame.target
          {
            counts[spot, default: 0] += 1
          }
          last = frame.stack.step == .curl ? frame.target : nil
          t += 30
        }
      }
      return counts
    }
    let soft = naps(fondOf: .soft)
    let rug = naps(fondOf: .rug)
    #expect((soft[.soft] ?? 0) > (rug[.soft] ?? 0))
    #expect((rug[.rug] ?? 0) > (soft[.rug] ?? 0))
  }

  @Test func experienceMovesThePersonality() {
    let nature = CatPersonality.even
    let play = (0..<40).map { Self.event(.play, "a", -60 + Double($0)) }
    let pets = (0..<40).map { Self.event(.pet, "b", -60 + Double($0)) }
    let played = nature.drifted(by: play, at: Self.at(4))
    let petted = nature.drifted(by: pets, at: Self.at(4))
    #expect(played.playful > nature.playful)
    #expect(played.lazy < nature.lazy)
    #expect(played.cuddly == nature.cuddly)
    #expect(petted.cuddly > nature.cuddly)
    #expect(petted.playful == nature.playful)
    // However much happens, a trait moves a little and stays inside 0…1.
    let lots = (0..<2000).map { Self.event(.play, "a", -100 + Double($0) * 0.05, $0) }
    let most = nature.drifted(by: lots, at: Self.at(4))
    #expect(most.playful <= nature.playful + CatPersonality.driftLimit + 1e-9)
    // A week ago is forgotten, and what has not happened yet does not count.
    let old = nature.drifted(by: play, at: Self.at(4 + 8 * 24))
    #expect(old == nature)
    #expect(nature.drifted(by: play, at: Self.at(-70)) == nature)
  }

  // MARK: - Personality

  @Test func personalityChangesWhatItDoes() {
    let playful = CatPersonality(lazy: 0.15, playful: 0.85, bold: 0.8)
    let lazy = CatPersonality(lazy: 0.85, playful: 0.15, bold: 0.2)
    var playfulPlay = 0.0
    var lazyPlay = 0.0
    var playfulRest = 0.0
    var lazyRest = 0.0
    for seed in UInt64(1)...4 {
      let one = Self.day(Self.bothActive, from: 7, hours: 14, seed: seed, personality: playful)
      let two = Self.day(Self.bothActive, from: 7, hours: 14, seed: seed, personality: lazy)
      playfulPlay += Self.share(one) { $0.group == .play || $0.group == .mischief }
      lazyPlay += Self.share(two) { $0.group == .play || $0.group == .mischief }
      playfulRest += Self.share(one) { $0.group == .rest }
      lazyRest += Self.share(two) { $0.group == .rest }
    }
    #expect(playfulPlay > lazyPlay * 1.3)
    #expect(lazyRest > playfulRest * 1.2)
  }

  @Test func seedsMakeDifferentCats() {
    let one = CatPersonality.seeded(StableHash.of("pair-1/ginger"))
    let two = CatPersonality.seeded(StableHash.of("pair-2/ginger"))
    #expect(one != two)
    #expect(one == CatPersonality.seeded(StableHash.of("pair-1/ginger")))
    for trait in CatPersonality.Trait.allCases {
      #expect(CatPersonality.seededRange.contains(one[trait]))
    }
    #expect(StableHash.of("billet") == 6_446_531_653_788_259_549)
  }

  // MARK: - Cost and shape

  @Test func decisionsAreRare() {
    let count = Self.fold(Self.bothActive, to: 24).transitions.filter { $0.at >= Self.at(0) }.count
    // A few thousand moves a day at most: far under one a second.
    #expect(count < 8000)
    #expect(count > 500)
  }

  @Test func reflexesAreStatelessAndBlink() {
    var blinks = 0
    var t = Self.at(12)
    while t < Self.at(12) + 120 {
      let one = CatReflexes.at(t, seed: 5, vitality: .awake)
      #expect(one == CatReflexes.at(t, seed: 5, vitality: .awake))
      if one.blink { blinks += 1 }
      t += 1.0 / 30
    }
    #expect(blinks > 0)
    #expect(!CatReflexes.at(t, seed: 5, vitality: .asleep).blink)
  }

  @Test func theDocIsDrawnFromTheChart() throws {
    let doc = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "../../docs/cat-brain.md").standardized
    var text = try String(contentsOf: doc, encoding: .utf8)
    // `BILLET_EXPORT_BRAIN=1 swift test --filter theDocIsDrawnFromTheChart` writes it again.
    if ProcessInfo.processInfo.environment["BILLET_EXPORT_BRAIN"] == "1",
      let open = text.range(of: "```mermaid\n"),
      let close = text.range(of: "\n```", range: open.upperBound..<text.endIndex)
    {
      text.replaceSubrange(open.upperBound..<close.lowerBound, with: CatStatechart.mermaid())
      try text.write(to: doc, atomically: true, encoding: .utf8)
    }
    #expect(text.contains(CatStatechart.mermaid()), "Export the chart again: docs/cat-brain.md")
    for step in CatActivityStep.allCases {
      #expect(
        CatStatechart.mermaid().contains(
          step.rawValue.prefix(1).uppercased() + step.rawValue.dropFirst()))
    }
  }

  // MARK: - Helpers

  static func hour(_ t: Double) -> Double {
    ((t - midnight) / 3600).truncatingRemainder(dividingBy: 24)
  }

  /// Folds `events` from 8 p.m. the day before to `hour`, keeping every transition.
  static func fold(_ events: [LifeEvent], to hour: Double, seed: UInt64 = 7) -> CatBrain {
    let start = at(-20)
    var sampler = CatLifeSampler(events: events, context: context)
    var config = CatBrainConfig()
    config.transitionCount = .max
    var brain = CatBrain(
      seed: seed, personality: .even, room: room, start: start, life: sampler.sample(at: start),
      utcOffset: 0, config: config)
    brain.remember(events.filter { $0.at.timeIntervalSince1970 < start })
    brain.schedule(events)
    brain.advance(to: at(hour), life: &sampler)
    return brain
  }
}
