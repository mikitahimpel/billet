import Foundation
import Testing

@testable import Pet

@Suite("CatUpbringing")
struct CatUpbringingTests {
  typealias Day = CatBrainTests

  static func learned(_ events: [LifeEvent], at hour: Double = 12) -> CatUpbringing {
    CatUpbringing.learned(from: events, at: Day.at(hour), utcOffset: 0)
  }

  /// `kind` every `every` hours over the `days` before noon, alternating partners.
  static func often(_ kind: LifeEvent.Kind, every: Double, days: Double, salt: Int = 1)
    -> [LifeEvent]
  {
    stride(from: 12 - days * 24, to: 12, by: every).enumerated().map { n, hour in
      Day.event(kind, n % 2 == 0 ? "a" : "b", hour, salt)
    }
  }

  // MARK: - Bounds

  @Test func everyCounterStaysBetweenZeroAndOne() {
    let flood =
      Self.often(.pet, every: 0.05, days: 6) + Self.often(.play, every: 0.05, days: 6, salt: 2)
      + Self.often(.shoo, every: 0.05, days: 6, salt: 3)
    let raised = Self.learned(flood)
    for value in [raised.affection, raised.playfulness, raised.aloofness, raised.stayingOff] {
      #expect((0...1).contains(value))
    }
    #expect(raised.affection > 0.99)
    for space in [0.0, 0.3, 1.0] {
      #expect((0...1).contains(raised.personalSpace(from: space)))
    }
    let neglected = Self.learned([Day.event(.pet, "a", -200)])
    #expect((0...1).contains(neglected.personalSpace(from: 1)))
    for group in CatActivityGroup.allCases {
      for raised in [raised, neglected, .none] {
        let bias = raised.bias(group, hour: 12)
        #expect(bias > 0.05 && bias < 4, "\(group) \(bias)")
      }
    }
  }

  @Test func aCatThatLearnedNothingIsItsTemperament() {
    for group in CatActivityGroup.allCases {
      #expect(CatUpbringing.none.bias(group, hour: 9) == 1)
    }
    #expect(CatUpbringing.none.personalSpace(from: 0.35) == 0.35)
    #expect(CatUpbringing.none.tricks.isEmpty)
    #expect(CatUpbringing.none.habits.isEmpty)
  }

  // MARK: - Decay

  @Test func aHabitFadesWhenTheCareStops() {
    let recent = Self.learned(Self.often(.pet, every: 3, days: 2))
    let older = Self.learned(Self.often(.pet, every: 3, days: 2).map { shifted($0, by: -3 * 24) })
    let gone = Self.learned(Self.often(.pet, every: 3, days: 2).map { shifted($0, by: -7 * 24) })
    #expect(recent.affection > older.affection * 2)
    #expect(gone.affection == 0)
    // Nothing from the future counts.
    #expect(Self.learned(Self.often(.pet, every: 3, days: 2), at: -48).affection == 0)
  }

  @Test func leftAloneItKeepsToItselfAndWarmsUpWithCare() {
    let cared = Self.often(.feed, every: 6, days: 6)
    #expect(Self.learned(cared).aloofness == 0)
    // Nobody for three days.
    let quiet = cared.filter { $0.at.timeIntervalSince1970 < Day.at(-60) }
    let alone = Self.learned(quiet)
    #expect(alone.aloofness > 0.9)
    // Then a few pets this morning.
    let back = quiet + (0..<3).map { Day.event(.pet, "a", 8 + Double($0), 7) }
    let warming = Self.learned(back)
    #expect(warming.aloofness < alone.aloofness)
    let more = back + (0..<8).map { Day.event(.note, "b", 9 + Double($0) / 3, 8) }
    #expect(Self.learned(more).aloofness < warming.aloofness * 0.5)
  }

  // MARK: - Habits

  @Test func mealsAtTheSameHourMakeAMealtime() {
    let dinners = (1...4).map {
      Day.event(.feed, "a", 20 + Double($0 % 3) * 0.2 - Double($0) * 24, 4)
    }
    let raised = Self.learned(dinners, at: 6)
    #expect(raised.mealHour == 20)
    #expect(raised.habits.contains("Waits for dinner at 8"))
    #expect(raised.isMealtime(at: Day.at(19.8), utcOffset: 0))
    #expect(!raised.isMealtime(at: Day.at(19), utcOffset: 0))
    // Two days are not yet a habit, and scattered meals never are.
    #expect(Self.learned(Array(dinners.prefix(2)), at: 6).mealHour == nil)
    let scattered = (1...5).map { Day.event(.feed, "a", Double($0 * 5) - Double($0) * 24, 4) }
    #expect(Self.learned(scattered, at: 6).mealHour == nil)
    // A mealtime keeps to the pair's own clock.
    let abroad = CatUpbringing.learned(from: dinners, at: Day.at(6), utcOffset: 3600)
    #expect(abroad.mealHour == 21)
  }

  @Test func morningPetsAreSaidInPlainWords() {
    let mornings = (1...5).flatMap { day in
      (0..<6).map { Day.event(.pet, "b", 8 + Double($0) * 0.15 - Double(day) * 24, day) }
    }
    let raised = Self.learned(mornings, at: 6)
    #expect(raised.petHour == 8)
    #expect(raised.habits.contains("Loves morning pets"))
    #expect(raised.habits.count <= 3)
  }

  @Test func careTeachesTricksAndTheyAreForgotten() {
    let loved = Self.often(.pet, every: 2, days: 4)
    #expect(Self.learned(loved).tricks.contains(.comesWhenCalled))
    #expect(!Self.learned(loved).tricks.contains(.highFive))
    let played = loved + Self.often(.play, every: 2, days: 4, salt: 2)
    #expect(Self.learned(played).tricks == [.comesWhenCalled, .highFive])
    #expect(Self.learned(played, at: 12 + 8 * 24).tricks.isEmpty)
  }

  @Test func shoosTeachItToStayOff() {
    let shoos = Self.often(.shoo, every: 10, days: 4)
    let raised = Self.learned(shoos)
    #expect(raised.stayingOff > 0.6)
    #expect(raised.bias(.mischief, hour: 12) < 0.75)
    #expect(raised.habits.contains("Stays off the desk"))
  }

  // MARK: - In the brain

  @Test func atMealtimeItWaitsByTheBowl() {
    let dinners = [-52.0, -28, -4].map { Day.event(.feed, "a", $0, 6) }
    let events = dinners + [Day.event(.pet, "b", 9), Day.event(.note, "a", 13)]
    var waited = 0
    for seed in UInt64(1)...4 {
      var runner = CatBrainRunner(
        events: events, now: Day.at(19.5), context: Day.context, seed: seed,
        temperament: .cuddler, room: Day.room)
      #expect(runner.brain.upbringing.mealHour == 20)
      var t = Day.at(19.5)
      var seen = false
      while t < Day.at(20.4) {
        runner.advance(to: t)
        if runner.frame.stack.step == .waitByBowl { seen = true }
        t += 5
      }
      if seen { waited += 1 }
    }
    #expect(waited >= 2)
  }

  @Test func aShooSendsItOffTheDesk() throws {
    let room = RoomAffordances(Day.room.all + [RoomAffordance(id: "desk", kind: .desk)])
    // Find a cat on the desk, then shoo it.
    var found: (CatBrainRunner, Double)?
    for seed in UInt64(1)...8 where found == nil {
      var runner = CatBrainRunner(
        events: Day.bothActive, now: Day.at(8), context: Day.context, seed: seed,
        temperament: .diva, room: room)
      var t = Day.at(8)
      while t < Day.at(20), runner.frame.stack.step != .sitOnDesk {
        t += 5
        runner.advance(to: t)
      }
      if runner.frame.stack.step == .sitOnDesk { found = (runner, t) }
    }
    let (shown, t) = try #require(found)
    var runner = shown
    let shoo = LifeEvent(
      id: UUID(), kind: .shoo, by: "a", at: Date(timeIntervalSince1970: t + 1))
    runner.receive([shoo], now: t + 1)
    runner.advance(to: t + 1.5)
    #expect(runner.frame.stack.step == .startle)
    let off = runner.brain.transitions.last { $0.to.step == .startle }
    #expect(off?.cause == .event)
    #expect(off?.from.step == .sitOnDesk)
  }

  @Test func shooedOftenItKeepsOffTheDesk() {
    let room = RoomAffordances(Day.room.all + [RoomAffordance(id: "desk", kind: .desk)])
    func onDesk(_ extra: [LifeEvent]) -> Double {
      (UInt64(1)...3).reduce(0) { sum, seed in
        var runner = CatBrainRunner(
          events: Day.bothActive + extra, now: Day.at(7), context: Day.context, seed: seed,
          temperament: .diva, room: room)
        var on = 0
        var all = 0
        var t = Day.at(7)
        while t < Day.at(21) {
          runner.advance(to: t)
          if CatUpbringing.shooable.contains(runner.frame.stack.step) { on += 1 }
          all += 1
          t += 5
        }
        return sum + Double(on) / Double(all)
      }
    }
    let shoos = (0..<8).map { Day.event(.shoo, "a", -60 + Double($0) * 7, 9) }
    #expect(onDesk(shoos) < onDesk([]) * 0.5)
  }

  // MARK: - Determinism

  @Test func theOrderEventsArriveInNeverMatters() {
    let events =
      Self.often(.pet, every: 3, days: 5) + Self.often(.feed, every: 8, days: 5, salt: 2)
      + Self.often(.shoo, every: 30, days: 5, salt: 3)
    var shuffler = SplitMix64(seed: 5)
    let shuffled = events.shuffled(using: &shuffler)
    #expect(Self.learned(events) == Self.learned(shuffled))
    #expect(Self.learned(events) == Self.learned(events + events))
  }

  @Test func aFreshReplayLearnedWhatALongRunDid() {
    let events = Day.bothActive + Self.often(.play, every: 5, days: 3, salt: 4)
    var long = CatBrainRunner(
      events: events, now: Day.at(-40), context: Day.context, seed: 3, temperament: .clown,
      room: Day.room)
    var t = Day.at(-40)
    while t < Day.at(14) {
      long.advance(to: t)
      t += 53
    }
    let fresh = CatBrainRunner.replay(
      events: events, now: t, context: Day.context, seed: 3, temperament: .clown, room: Day.room)
    long.advance(to: t)
    #expect(fresh.upbringing == long.brain.upbringing)
    #expect(fresh.frame() == long.brain.frame())
    #expect(fresh.upbringing.playfulness > 0)
  }

  // MARK: - Sync and the play machine

  @Test func aSavedLogSkipsAnEventItCannotRead() throws {
    let pet = Day.event(.pet, "a", 9)
    var json = try #require(
      String(
        data: JSONEncoder().encode(LifeLog([pet, Day.event(.feed, "b", 10)])), encoding: .utf8))
    json = json.replacingOccurrences(of: "\"feed\"", with: "\"purr\"")
    let log = try JSONDecoder().decode(LifeLog.self, from: Data(json.utf8))
    #expect(log.all == [pet])
  }

  @Test func aCatThatComesWhenCalledAlwaysComes() {
    var play = CatPlay()
    var now = 0.0
    var ignored = 0
    for _ in 0..<12 {
      if play.handle(.called, at: now)?.reaction == .ignore { ignored += 1 }
      now += 4
    }
    #expect(ignored > 0)
    var taught = CatPlay()
    taught.learned = [.comesWhenCalled]
    now = 0
    for _ in 0..<12 {
      #expect(taught.handle(.called, at: now)?.reaction != .ignore)
      now += 4
    }
  }

  @Test func onlyACatThatLearnedItGivesAHighFive() {
    func tricks(_ learned: Set<CatLearnedTrick>) -> Set<CatTrick> {
      var play = CatPlay()
      play.learned = learned
      var seen = Set<CatTrick>()
      for n in 0..<8 {
        if case .trick(let trick) = play.handle(.trickAsked, at: Double(n) * 120)?.reaction {
          seen.insert(trick)
        }
      }
      return seen
    }
    #expect(!tricks([]).contains(.highFive))
    #expect(tricks([.highFive]).contains(.highFive))
    #expect(tricks([.highFive]).isSuperset(of: [.sit, .wave]))
  }

  private func shifted(_ event: LifeEvent, by hours: Double) -> LifeEvent {
    LifeEvent(
      id: event.id, kind: event.kind, by: event.by, at: event.at.addingTimeInterval(hours * 3600))
  }
}
