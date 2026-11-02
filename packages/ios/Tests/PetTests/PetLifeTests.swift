import Foundation
import Testing

@testable import Pet

@Suite("PetLife")
struct PetLifeTests {
  private static let me = "phone-a"
  private static let them = "phone-b"
  /// Midnight UTC on a Monday, so hours read straight off the clock with a zero offset.
  private static let midnight = Date(timeIntervalSince1970: 1_793_577_600)
  private static let context = LifeContext(partners: [me, them], utcOffset: 0)

  private static func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }

  private static func event(_ kind: LifeEvent.Kind, by: String = me, _ hours: Double) -> LifeEvent {
    LifeEvent(kind: kind, by: by, at: at(hours))
  }

  /// The state with the pet born at its first event, as a phone sees it.
  private static func state(
    _ events: [LifeEvent], _ hours: Double, context: LifeContext = context,
    config: LifeConfig = .standard
  ) -> LifeState {
    var context = context
    context.born = context.born ?? events.map(\.at).min()
    return PetLife.state(events: events, now: at(hours), context: context, config: config)
  }

  @Test func decayFallsTowardTheFloorFastWhenFullAndSlowWhenLow() {
    let config = LifeConfig.standard
    let high = 1 - PetLife.decay(1, toward: config.floor, hours: 2, tau: config.fullHours)
    let low = 0.3 - PetLife.decay(0.3, toward: config.floor, hours: 2, tau: config.fullHours)
    #expect(high > low * 5)
    #expect(
      abs(PetLife.decay(1, toward: 0.2, hours: 8, tau: 8) - (0.2 + 0.8 * exp(-1))) < 1e-12)
  }

  @Test func noNeedEverFallsBelowTheFloor() {
    let away = Self.state([Self.event(.feed, 0), Self.event(.note, 0)], 24 * 6)
    for need in PetNeed.allCases {
      #expect(away.needs[need] >= LifeConfig.standard.floor - 1e-9)
    }
    #expect(away.mood >= LifeConfig.standard.floor - 1e-9)
  }

  @Test func aFewDaysAwayHurtLittleMore() {
    let config = LifeConfig.standard
    let dayOne = PetLife.decay(1, toward: config.floor, hours: 24, tau: config.lovedHours)
    let dayThree = PetLife.decay(1, toward: config.floor, hours: 72, tau: config.lovedHours)
    #expect((1 - dayOne) > (dayOne - dayThree) * 1.5)
  }

  @Test func gainsDiminishAsTheNeedFills() {
    var full = 0.3
    var steps: [Double] = []
    for _ in 0..<5 {
      let next = PetLife.gain(full, by: 0.45, returns: 1.5)
      steps.append(next - full)
      full = next
    }
    #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 > $1 })
    #expect(steps[4] < steps[0] / 5)
    #expect(full <= 1)
  }

  @Test func treatsInARowGiveLessEachTime() {
    // Born a day earlier, so it is hungry by the time the treats come.
    let born = Self.event(.pet, 0)
    let fed = (0..<5).map { Self.event(.feed, 24 + Double($0) / 60) }
    let full = { (count: Int) in Self.state([born] + fed.prefix(count), 24.1).needs.full }
    #expect(full(5) - full(4) < (full(1) - full(0)) / 5)
  }

  @Test func sleepinessPeaksAtThreeInTheNight() {
    #expect(abs(PetLife.sleepiness(hour: 3) - 1) < 1e-12)
    #expect(abs(PetLife.sleepiness(hour: 15)) < 1e-12)
    #expect(PetLife.sleepiness(hour: 23) > PetLife.sleepiness(hour: 19))
  }

  @Test func itSleepsAtNightAndIsUpByDay() {
    let night = Self.state([], 24 * 7 + 3)
    let day = Self.state([], 24 * 7 + 14)
    #expect(night.asleep)
    #expect(!day.asleep)
    #expect(night.needs.rested > day.needs.rested - 0.3)
  }

  @Test func theDayRhythmFollowsThePairsOwnClock() {
    // 3 in the morning UTC is noon in Tokyo.
    let tokyo = LifeContext(partners: [Self.me, Self.them], utcOffset: 9 * 3600)
    #expect(Self.state([], 24 * 7 + 3).asleep)
    #expect(!Self.state([], 24 * 7 + 3, context: tokyo).asleep)
  }

  @Test func somethingWakesItAndItStaysUpAWhile() {
    let woken = [Self.event(.pet, 24 * 7 + 2)]
    #expect(!Self.state(woken, 24 * 7 + 2.1).asleep)
    #expect(Self.state(woken, 24 * 7 + 4).asleep)
  }

  @Test func lovedIsTheSoftMinimumOfBothPartners() {
    let soft = PetLife.softMin([0.9, 0.3], sharpness: 10)
    #expect(soft > 0.3 && soft < 0.4)
    #expect(abs(PetLife.softMin([0.6, 0.6], sharpness: 10) - 0.6) < 1e-12)
  }

  @Test func onePartnerAloneIsNotEnoughAndTheOtherIsMissed() {
    let mine = (0..<12).map { Self.event(.pet, by: Self.me, 24 * 6 + Double($0) * 2) }
    let both = mine + (0..<12).map { Self.event(.pet, by: Self.them, 24 * 6 + Double($0) * 2) }
    let alone = Self.state(mine, 24 * 7)
    let together = Self.state(both, 24 * 7)
    #expect(alone.missing == Self.them)
    #expect(together.missing == nil)
    #expect(together.needs.loved > alone.needs.loved + 0.15)
    #expect(alone.love[Self.me, default: 0] > alone.love[Self.them, default: 0])
  }

  @Test func aNoteFillsLovedForBothAndMoreThanAPet() {
    let base = 24.0 * 7
    let note = Self.state([Self.event(.note, by: Self.them, base)], base)
    let pet = Self.state([Self.event(.pet, by: Self.them, base)], base)
    #expect(note.needs.loved > pet.needs.loved)
    #expect(note.love[Self.me] == note.love[Self.them])
  }

  @Test func aPartnerNotYetKnownIsMissedAndTheirCareStillCounts() {
    let half = LifeContext(partners: [Self.me], utcOffset: 0)
    let base = 24.0 * 7
    let stranger = Self.state([Self.event(.pet, by: "someone", base)], base, context: half)
    let nobody = Self.state([], base, context: half)
    #expect(stranger.needs.loved > nobody.needs.loved)
    #expect(stranger.love.count == 2)
  }

  @Test func theFakePartnersEventsCount() {
    let fake = LifeContext(partners: [Self.me, "fake-partner"], utcOffset: 0)
    let base = 24.0 * 7
    let petted = Self.state([Self.event(.pet, by: "fake-partner", base)], base, context: fake)
    #expect(
      petted.love["fake-partner", default: 0]
        > Self.state([], base, context: fake)
        .love["fake-partner", default: 0])
  }

  @Test func thePorchLightFreezesDecay() {
    let base = 24.0 * 7
    let fed = [Self.event(.feed, base - 48)]
    let frozen = LifeContext(
      partners: [Self.me, Self.them], utcOffset: 0,
      frozen: [DateInterval(start: Self.at(base - 48), end: Self.at(base))])
    let held = Self.state(fed, base, context: frozen)
    let fell = Self.state(fed, base)
    let justFed = Self.state(fed, base - 48)
    // Only what is left of the start, a week back, differs.
    #expect(abs(held.needs.full - justFed.needs.full) < 1e-5)
    #expect(fell.needs.full < held.needs.full - 0.2)
  }

  @Test func twoPhonesAgreeOnTheSameEvents() {
    let kinds: [LifeEvent.Kind] = [.feed, .pet, .play, .note, .sleep]
    var random = SplitMix64(seed: 7)
    let events = (0..<80).map { i in
      LifeEvent(
        kind: kinds[i % kinds.count], by: i.isMultiple(of: 3) ? Self.them : Self.me,
        at: Self.at(Double(random.next() % 600) / 4))
    }
    // The other phone got them in another order, some twice, and asks at the same moment.
    let other = (events.reversed() + events.prefix(10)).shuffled(using: &random)
    let now = 24 * 6.5
    let a = Self.state(events, now)
    let b = Self.state(other, now)
    #expect(a == b)
    // The widget, asking ahead, sees the same as a phone asking at that moment.
    var context = Self.context
    context.born = events.map(\.at).min()
    let ahead = PetLife.forecast(events: events, at: [Self.at(now)], context: context)
    #expect(ahead.first == a)
  }

  @Test func eventsAfterNowDoNotCount() {
    let later = [Self.event(.feed, 24 * 7 + 1)]
    #expect(Self.state(later, 24 * 7) == Self.state([], 24 * 7))
  }

  @Test func aNewPetStartsAtTheInitialValuesAndAnOldOneFromAWeekBack() {
    let config = LifeConfig.standard
    let newborn = Self.state([], 24 * 7 + 12)
    #expect(abs(newborn.needs.full - config.initial) < 1e-12)
    // Born a month ago and left alone since: as low as it gets, and it does not matter how long.
    let born = LifeContext(partners: [Self.me, Self.them], utcOffset: 0, born: Self.at(-24 * 30))
    let lonely = Self.state([], 24 * 7 + 12, context: born)
    let lonelier = Self.state([], 24 * 9 + 12, context: born)
    #expect(lonely.needs.full < config.floor + 0.01)
    #expect(abs(lonely.needs.full - lonelier.needs.full) < 1e-6)
  }

  @Test func theLifeIsContinuousAsItsBirthPassesOutOfTheWindow() {
    let born = [Self.event(.feed, 0)]
    let horizon = LifeConfig.standard.horizonHours
    let before = Self.state(born, horizon - 0.001)
    let after = Self.state(born, horizon + 0.001)
    #expect(abs(before.needs.loved - after.needs.loved) < 1e-3)
    #expect(abs(before.needs.full - after.needs.full) < 1e-3)
  }

  @Test func moodIsPulledDownMostByTheLowestNeed() {
    let even = PetNeeds(all: 0.6).mood(weights: LifeConfig.standard.weights)
    var lonely = PetNeeds(all: 0.8)
    lonely.loved = 0.2
    var hungry = PetNeeds(all: 0.8)
    hungry.full = 0.2
    let weights = LifeConfig.standard.weights
    #expect(abs(even - 0.6) < 1e-9)
    #expect(lonely.mood(weights: weights) < hungry.mood(weights: weights))
  }

  @Test func theConfigDecodesPartialOverrides() throws {
    let json = Data(#"{"fullHours": 4, "unknown": 1}"#.utf8)
    let config = try JSONDecoder().decode(LifeConfig.self, from: json)
    #expect(config.fullHours == 4)
    #expect(config.lovedHours == LifeConfig.standard.lovedHours)
    let round = try JSONDecoder().decode(
      LifeConfig.self, from: JSONEncoder().encode(config))
    #expect(round == config)
  }
}

@Suite("NeedFocus")
struct NeedFocusTests {
  @Test func aNeedHoveringAtTheLineDoesNotFlicker() {
    var focus = NeedFocus()
    var hungry = PetNeeds(all: 0.9)
    hungry.full = 0.34
    #expect(focus.update(hungry) == .full)
    for value in [0.36, 0.4, 0.45, 0.49, 0.38, 0.5] {
      hungry.full = value
      #expect(focus.update(hungry) == .full)
    }
    hungry.full = 0.51
    #expect(focus.update(hungry) == nil)
    hungry.full = 0.4
    #expect(focus.update(hungry) == nil)
  }

  @Test func theMostUrgentNeedIsUsuallyChosen() {
    var needs = PetNeeds(all: 0.9)
    needs.full = 0.3
    needs.rested = 0.1
    let odds = NeedFocus.probabilities([.full, .rested], values: needs, temperature: 0.08)
    #expect(odds[1] > 0.9)
    #expect(abs(odds.reduce(0, +) - 1) < 1e-12)
    var counts: [PetNeed: Int] = [:]
    for seed in 1...200 {
      var focus = NeedFocus(seed: UInt64(seed))
      if let need = focus.update(needs) { counts[need, default: 0] += 1 }
    }
    #expect(counts[.rested, default: 0] > counts[.full, default: 0] * 5)
    #expect(counts[.full, default: 0] > 0)
  }

  @Test func itKeepsItsFocusUntilThatNeedIsMet() {
    var focus = NeedFocus()
    var needs = PetNeeds(all: 0.9)
    needs.playful = 0.3
    #expect(focus.update(needs) == .playful)
    needs.full = 0.1
    #expect(focus.update(needs) == .playful)
    needs.playful = 0.8
    #expect(focus.update(needs) == .full)
  }

  @Test func aContentPetHasNoFocus() {
    var focus = NeedFocus()
    #expect(focus.update(PetNeeds(all: 0.7)) == nil)
  }
}
