import Foundation
import Testing

@testable import Pet

/// Keeps "interesting to watch" true: over simulated days, in a few rooms and for each type of cat,
/// no group takes over the day, every waking hour has something to see, nothing repeats back to
/// back, and the rare things stay rare.
@Suite("Cat life statistics")
struct CatLifeStatisticsTests {
  typealias Day = CatBrainTests
  static let seeds: [UInt64] = [1, 7, 42, 99]

  static let all: [(String, CatLifeAudit)] = {
    var out: [(String, CatLifeAudit)] = []
    for seed in seeds {
      out.append(("nooki \(seed)", CatAuditTests.audit(seed: seed)))
      out.append(("styled \(seed)", CatAuditTests.audit(seed: seed, room: Day.room)))
    }
    for type in CatTemperament.allCases {
      out.append(("\(type.title)", CatAuditTests.audit(seed: 7, temperament: type)))
    }
    return out
  }()

  static func audits() -> [(String, CatLifeAudit)] { all }

  @Test("no group takes over the day")
  func shareCaps() {
    for (name, audit) in Self.audits() {
      let sleepy = name == "Sleepyhead"
      for group in CatActivityGroup.allCases {
        var cap: Double = group == .rest ? 0.65 : group == .idle ? 0.25 : 0.3
        if sleepy && group == .rest { cap = 0.8 }
        if name == "Clown" && group == .play { cap = 0.4 }
        #expect(audit.share(of: group) <= cap, "\(name): \(group) \(audit.share(of: group))")
      }
      #expect(audit.asleepShare < (sleepy ? 0.7 : 0.6), "\(name): asleep \(audit.asleepShare)")
    }
  }

  @Test("an awake hour always has several different things in it")
  func everyHourHasSomethingToSee() {
    for (name, audit) in Self.audits() {
      for hour in 8..<22 {
        #expect(audit.distinctSteps(hour: hour) >= 4, "\(name): hour \(hour)")
        #expect(audit.distinctSteps(hour: hour, visible: true) >= 2, "\(name): hour \(hour)")
      }
      let wanted = name == "Sleepyhead" ? 0.1 : 0.2
      #expect(audit.activeShare() >= wanted, "\(name): active \(audit.activeShare())")
      #expect(audit.longestDull <= 20 * 60, "\(name): dull \(audit.longestDull / 60) min")
    }
  }

  @Test("nothing is played twice running, and the same group is not drawn again and again")
  func noRepeats() {
    for (name, audit) in Self.audits() {
      #expect(audit.stepRepeats == 0, "\(name): \(audit.stepRepeats) repeated steps")
      let episodes = audit.episodes.count
      #expect(audit.flipFlops() <= episodes / 4, "\(name): \(audit.flipFlops()) flip-flops")
    }
  }

  @Test("a story is rarely played again within the next two")
  func scriptsRotate() {
    for seed in Self.seeds {
      var runner = CatBrainRunner(
        events: Day.bothActive, now: Day.at(4), context: Day.context, seed: seed,
        room: CatBrainTests.room)
      runner.advance(to: Day.at(4) + 86400)
      let brain = runner.brain
      #expect(brain.scriptsPlayed > 100, "seed \(seed): \(brain.scriptsPlayed) scripts")
      #expect(
        Double(brain.scriptsRepeated) <= 0.12 * Double(brain.scriptsPlayed),
        "seed \(seed): \(brain.scriptsRepeated) of \(brain.scriptsPlayed)")
    }
  }

  @Test("a game or a wander lasts a while: most lively episodes are half a minute or more")
  func sessionsLast() {
    for (name, audit) in Self.audits() {
      let lively = audit.episodes.filter { [.play, .explore, .groom].contains($0.group) }
      let long = lively.filter { $0.length >= 30 }.count
      #expect(Double(long) >= 0.3 * Double(lively.count), "\(name): \(long) of \(lively.count)")
    }
  }

  @Test("rare things happen now and then, never too often")
  func rareThings() {
    var noises = 0
    var tails = 0
    var days = 0
    for (name, audit) in Self.audits() {
      let n = audit.count(of: .heardNoise)
      let c = audit.count(of: .chaseTail)
      #expect(n <= 6, "\(name): \(n) noises")
      #expect(c <= 3, "\(name): \(c) tail chases")
      noises += n
      tails += c
      days += 1
    }
    #expect(noises >= days / 2, "noises over \(days) days: \(noises)")
    #expect(tails >= 1, "tail chases over \(days) days: \(tails)")
  }

  @Test("the new stories are all played in a day or two")
  func storiesAppear() {
    var seen = Set<CatActivityStep>()
    for (_, audit) in Self.audits() { seen.formUnion(audit.segments.map(\.step)) }
    for step: CatActivityStep in [
      .spotMote, .windUp, .shakeOff, .skid, .trackMover, .chatter, .bask, .glanceBack, .heardNoise,
    ] {
      #expect(seen.contains(step), "\(step) never played")
    }
  }

  @Test("the same seed lives the same day")
  func deterministic() {
    #expect(CatAuditTests.audit(seed: 5).segments == CatAuditTests.audit(seed: 5).segments)
  }

  @Test("yesterday's hours lean today's choices a little")
  func habits() {
    var memory = CatMemory()
    memory.spent(.play, hour: 19, seconds: 1500)
    memory.spent(.groom, hour: 19, seconds: 500)
    memory.spent(.rest, hour: 19, seconds: 900)
    let next = memory.carried()
    #expect(next.habit(.play, hour: 19) == 1 + 0.8 * 0.75)
    #expect(next.habit(.groom, hour: 19) > 1)
    #expect(next.habit(.play, hour: 7) == 1)
    #expect(next.habit(.rest, hour: 19) == 1)
    #expect(memory.habit(.play, hour: 19) == 1)
  }
}

@Suite("Cat observatory")
struct CatObservatoryTests {
  @Test("the clock changes speed without a jump")
  func clock() {
    var clock = CatClock(now: 1000)
    #expect(clock.sim(at: 1010) == 1010)
    clock.set(speed: 60, at: 1010)
    #expect(clock.sim(at: 1010) == 1010)
    #expect(clock.sim(at: 1020) == 1010 + 600)
    clock.set(speed: 1, at: 1020)
    #expect(clock.sim(at: 1030) == 1610 + 10)
  }

  @Test("it keeps the last twenty stretches and writes a log")
  func timeline() {
    var observatory = CatObservatory()
    let steps: [CatActivityStep] = [.sit, .lookAround, .groomPaw, .stalk, .windUp, .pounce]
    for i in 0..<30 {
      let stack = CatBrainStack(vitality: .awake, step: steps[i % steps.count])
      observatory.observe(stack, at: Double(i) * 10, cause: "chosen")
      observatory.observe(stack, at: Double(i) * 10 + 5, cause: "chosen")
    }
    #expect(observatory.episodes.count == CatObservatory.capacity)
    #expect(observatory.episodes.last?.end == nil)
    #expect(observatory.episodes.dropLast().allSatisfy { $0.end != nil })
    let log = observatory.log(now: 300, speed: 60, utcOffset: 0, seed: 7, top: [])
    #expect(log.hasPrefix("cat-log seed=7 at 00:05:00 x60"))
    #expect(log.components(separatedBy: "\n").count == 1 + CatObservatory.capacity)
  }

  @Test("forcing a group plays one of its scripts at once")
  func force() {
    var runner = CatBrainRunner(
      events: [], now: CatBrainTests.at(12), context: CatBrainTests.context, seed: 3,
      room: CatBrainTests.room)
    for group in CatActivityGroup.chosen {
      runner.force(group)
      #expect(runner.frame.stack.group == group, "\(group)")
    }
    runner.force(.react)
    #expect(runner.frame.stack.group == CatActivityGroup.chosen.last)
  }
}
