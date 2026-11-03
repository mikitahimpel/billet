import Foundation
import Testing

@testable import Pet

@Suite("CatTemperament")
struct CatTemperamentTests {
  typealias Day = CatBrainTests

  @Test(arguments: CatTemperament.allCases)
  func eachTypeFitsItsOwnHeart(_ type: CatTemperament) {
    #expect(CatTemperament.fitting(type.archetype) == type)
  }

  @Test func theTypesAreAboutEquallyCommon() {
    var counts: [CatTemperament: Int] = [:]
    let cats = 2000
    for n in 0..<cats {
      counts[CatTemperament.born(seed: StableHash.of("pair-\(n)/detailed/natural")), default: 0] +=
        1
    }
    for type in CatTemperament.allCases {
      let share = Double(counts[type] ?? 0) / Double(cats)
      #expect(share > 0.1 && share < 0.32, "\(type): \(share)")
    }
  }

  @Test func aSeedIsBornWithOneTemperamentForLife() {
    let seed = StableHash.of("pair-7/detailed/natural")
    let first = CatTemperament.born(seed: seed)
    for _ in 0..<5 { #expect(CatTemperament.born(seed: seed) == first) }
    #expect(CatTemperament.born(seed: seed) == CatTemperament.fitting(.seeded(seed)))
  }

  @Test(arguments: CatTemperament.allCases)
  func theNatureLeansToTheTypeAndKeepsTheSeed(_ type: CatTemperament) {
    let one = CatPersonality.seeded(11)
    let two = CatPersonality.seeded(12)
    let natureOne = type.nature(from: one)
    #expect(natureOne != type.nature(from: two))
    for trait in CatPersonality.Trait.allCases {
      let before = abs(one[trait] - type.archetype[trait])
      let after = abs(natureOne[trait] - type.archetype[trait])
      #expect(abs(after - before * (1 - CatTemperament.pull)) < 1e-9)
      #expect((0...1).contains(natureOne[trait]))
    }
    #expect(CatTemperament.fitting(natureOne) == type)
  }

  @Test(arguments: CatTemperament.allCases)
  func whatItDoesAfterATouchIsALegalScript(_ type: CatTemperament) throws {
    guard let script = type.afterTouch else { return }
    let first = try #require(script.first)
    #expect(CatStatechart.scripts(first.group).contains(script))
    #expect(CatStatechart.isLegal(from: .sit, to: first, cause: .event))
  }

  @Test(arguments: CatTemperament.allCases)
  func everyTransitionIsLegal(_ type: CatTemperament) {
    var illegal: [CatBrainTransition] = []
    for transition in Self.fold(type, Day.bothActive + Self.pets, to: 22).transitions {
      let activityOK =
        transition.from.step == transition.to.step
        || CatStatechart.isLegal(
          from: transition.from.step, to: transition.to.step, cause: transition.cause)
      let vitalityOK = CatStatechart.isLegal(
        from: transition.from.vitality, to: transition.to.vitality)
      if !activityOK || !vitalityOK { illegal.append(transition) }
    }
    #expect(illegal.isEmpty, "\(type): \(illegal.prefix(3))")
  }

  // MARK: - Told apart

  @Test func eachTypeLivesItsOwnDay() {
    func share(_ type: CatTemperament, _ groups: Set<CatActivityGroup>) -> Double {
      (UInt64(1)...3).reduce(0) { sum, seed in
        sum
          + Day.share(Self.day(type, seed: seed)) {
            $0.vitality == .awake && groups.contains($0.group)
          }
      }
    }
    #expect(share(.clown, [.play, .mischief]) > share(.sleepyhead, [.play, .mischief]) * 1.5)
    #expect(share(.sleepyhead, [.rest, .idle]) > share(.clown, [.rest, .idle]) * 1.2)
    #expect(share(.cuddler, [.social]) > share(.diva, [.social]) * 1.3)
    #expect(share(.explorer, [.explore]) > share(.sleepyhead, [.explore]) * 1.3)
    #expect(share(.diva, [.groom]) > share(.cuddler, [.groom]) * 1.3)
  }

  @Test func theBodyMovesAsItsTypeDoes() {
    let lively = CatTemperament.clown
    let slow = CatTemperament.sleepyhead
    #expect(lively.tempo > 1.15 && slow.tempo < 0.85)
    #expect(lively.amplitude > slow.amplitude)
    #expect(CatTemperament.cuddler.personalSpace < CatTemperament.diva.personalSpace)
    let frame = CatBrainRunner(
      events: Day.bothActive, now: Day.at(10), context: Day.context, seed: 5, temperament: lively,
      room: Day.room
    ).frame
    #expect(frame.tempo == lively.tempo)
    #expect(frame.amplitude == lively.amplitude)
    #expect(frame.personalSpace == lively.personalSpace)
  }

  @Test func anAwakeCatAnswersAPetAsItsTypeDoes() {
    var answered = 0
    for type in CatTemperament.allCases {
      guard let script = type.afterTouch else { continue }
      for hour in [10.0, 13.0, 16.0, 20.0] {
        let pet = Day.event(.pet, "a", hour + 30 / 3600.0, 9)
        let events = Day.bothActive + [pet]
        let before = CatBrainRunner.replay(
          events: Day.bothActive, now: Day.at(hour), context: Day.context, seed: 4,
          temperament: type, room: Day.room)
        guard before.stack.vitality == .awake, before.stack.step != .curl else { continue }
        let after = CatBrainRunner.replay(
          events: events,
          now: Day.at(hour) + 30 + CatBrainConfig.standard.petEcho + 0.5, context: Day.context,
          seed: 4, temperament: type, room: Day.room)
        guard after.stack.vitality == .awake else { continue }
        #expect(after.stack.step == script.first, "\(type) at \(hour)")
        answered += 1
      }
    }
    #expect(answered >= 4)
  }

  // MARK: - Determinism

  @Test(arguments: CatTemperament.allCases)
  func aFreshReplayEqualsALongRun(_ type: CatTemperament) {
    var long = CatBrainRunner(
      events: Day.bothActive, now: Day.at(-30), context: Day.context, seed: 3, temperament: type,
      room: Day.room)
    var t = Day.at(-30)
    while t < Day.at(14) {
      long.advance(to: t)
      t += 41
    }
    let fresh = CatBrainRunner.replay(
      events: Day.bothActive, now: t, context: Day.context, seed: 3, temperament: type,
      room: Day.room)
    long.advance(to: t)
    #expect(fresh.frame() == long.brain.frame())
    #expect(fresh.personality == long.brain.personality)
    #expect(fresh.nature == CatBrain.nature(seed: 3, temperament: type))
  }

  // MARK: - Helpers

  /// A pet every two hours through the day, so each type gets touched while awake.
  static let pets: [LifeEvent] = (0..<7).map { Day.event(.pet, "b", 8 + Double($0) * 2 + 0.3, 5) }

  /// The stack every five seconds from 7 a.m. to 9 p.m., for a cat of `type`.
  static func day(_ type: CatTemperament, seed: UInt64) -> [(Double, CatBrainStack)] {
    var runner = CatBrainRunner(
      events: Day.bothActive, now: Day.at(7), context: Day.context, seed: seed, temperament: type,
      room: Day.room)
    var out: [(Double, CatBrainStack)] = []
    var t = Day.at(7)
    while t < Day.at(21) {
      runner.advance(to: t)
      out.append((t, runner.frame.stack))
      t += 5
    }
    return out
  }

  /// Folds `events` from 8 p.m. the day before to `hour`, keeping every transition.
  static func fold(_ type: CatTemperament, _ events: [LifeEvent], to hour: Double) -> CatBrain {
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
