import Foundation
import Testing

@testable import Pet

@Suite("Need levels")
struct NeedLevelTests {
  @Test(arguments: [
    (1.0, NeedLevel.content), (0.7, .content), (0.69, .okay), (0.35, .okay), (0.34, .wants),
    (0.0, .wants), (-1.0, .wants), (Double.nan, .wants),
  ])
  func aValueReadsAsOneLevel(value: Double, level: NeedLevel) {
    #expect(NeedLevel(value) == level)
  }

  @Test func theScreenAndTheBrainDrawTheSameLowLine() {
    #expect(NeedLevel.wantsBelow == LifeConfig.standard.lowBelow)
  }

  @Test func theOrderShownHoldsEveryNeedOnce() {
    #expect(Set(PetNeed.displayOrder) == Set(PetNeed.allCases))
    #expect(PetNeed.displayOrder.count == PetNeed.allCases.count)
  }

  @Test(arguments: PetNeed.allCases)
  func theAskFitsUnderHerPortrait(need: PetNeed) {
    #expect(!need.ask.isEmpty && need.ask.count <= 7)
  }

  @Test(arguments: [
    (0.2, 20), (0.996, 100), (1.4, 100), (-0.3, 0), (Double.nan, 0), (Double.infinity, 0),
  ])
  func aPercentageStaysBetweenZeroAndAHundred(value: Double, percent: Int) {
    #expect(PetNeed.percent(value) == percent)
  }

  @Test func onlyTheLowestNeedIsRaisedAndOnlyWhileItWants() {
    #expect(NeedLevel.cue(PetNeeds(all: 0.9)) == nil)
    #expect(NeedLevel.cue(PetNeeds(all: 0.35)) == nil)
    #expect(NeedLevel.cue(PetNeeds(full: 0.3, rested: 0.9, loved: 0.1, playful: 0.2)) == .loved)
  }
}

@Suite("Need forecast")
struct NeedForecastTests {
  let config = LifeConfig.standard

  @Test func theHoursAreTheInverseOfTheLifesOwnDecay() throws {
    for (need, tau) in [(PetNeed.full, config.fullHours), (.playful, config.playfulHours)] {
      let hours = try #require(
        NeedForecast.hoursUntil(below: config.lowBelow, from: 0.9, floor: config.floor, tau: tau))
      let after = PetLife.decay(0.9, toward: config.floor, hours: hours, tau: tau)
      #expect(abs(after - config.lowBelow) < 1e-9, "\(need)")
    }
  }

  @Test func aValueAlreadyUnderTheLineTakesNoTime() {
    #expect(NeedForecast.hoursUntil(below: 0.35, from: 0.3, floor: 0.2, tau: 6) == 0)
  }

  @Test(arguments: [
    (0.2, 0.9, 0.2, 6.0),  // a line at the floor is never crossed
    (0.1, 0.9, 0.2, 6.0),  // nor one under it
    (0.35, 0.9, 0.2, 0.0),  // no time constant
    (0.35, 0.9, 0.2, -3.0),
    (0.35, Double.nan, 0.2, 6.0),
    (Double.nan, 0.9, 0.2, 6.0),
    (0.35, 0.9, 0.2, Double.infinity),
  ])
  func whatNeverFallsHasNoTime(threshold: Double, value: Double, floor: Double, tau: Double) {
    #expect(
      NeedForecast.hoursUntil(below: threshold, from: value, floor: floor, tau: tau) == nil)
  }

  @Test func asleepSheGetsHungryHalfAsFast() {
    let needs = PetNeeds(all: 0.6)
    #expect(NeedForecast.outlook(.full, in: needs, asleep: false) == .lowIn(.hours(6)))
    #expect(NeedForecast.outlook(.full, in: needs, asleep: true) == .lowIn(.hours(12)))
  }

  @Test(arguments: [
    (PetNeed.full, 0.3, false, NeedOutlook.wantsNow),
    (.full, 0.36, false, .lowIn(.soon)),
    (.full, 0.5, false, .lowIn(.hours(4))),
    (.playful, 0.9, false, .lowIn(.hours(15))),
    (.loved, 0.9, false, .lowIn(.hours(22))),
    (.loved, 1.0, false, .lowIn(.hours(23))),
    (.rested, 0.9, false, .steady),
    (.rested, 0.4, false, .lowIn(.hours(5))),
    (.rested, 0.3, false, .wantsNow),
    (.rested, 0.4, true, .metIn(.hours(2))),
    (.rested, 0.68, true, .metIn(.soon)),
    (.rested, 0.9, true, .steady),
    (.full, Double.nan, false, .steady),
  ])
  func eachNeedHasAnOutlook(need: PetNeed, value: Double, asleep: Bool, outlook: NeedOutlook) {
    #expect(NeedForecast.outlook(need, in: PetNeeds(all: value), asleep: asleep) == outlook)
  }

  @Test(arguments: [
    (0.0, NeedSpan?.some(.soon)), (0.74, .soon), (0.75, .hours(1)), (1.4, .hours(1)),
    (1.5, .hours(2)), (24.0, .hours(24)), (24.1, nil), (-0.1, nil), (Double.nan, nil),
    (Double.infinity, nil),
  ])
  func aSpanIsWholeHoursWithinADay(hours: Double, span: NeedSpan?) {
    #expect(NeedSpan(hours: hours) == span)
  }

  @Test func aTargetRestOnlyApproachesIsNeverReached() {
    #expect(NeedForecast.hoursAsleepUntil(rested: 1, from: 0.5) == nil)
    #expect(NeedForecast.hoursAsleepUntil(rested: 0.7, from: 0.8) == 0)
    #expect(NeedForecast.hoursAsleepUntil(rested: 0.7, from: .nan) == nil)
  }

  @Test(arguments: [
    (PetNeed.full, NeedOutlook.lowIn(.hours(2)), "Hungry in about 2 h"),
    (.full, .lowIn(.soon), "Hungry soon"),
    (.full, .wantsNow, "Would love a meal"),
    (.playful, .lowIn(.hours(4)), "Bored in about 4 h"),
    (.loved, .lowIn(.hours(9)), "Lonely in about 9 h"),
    (.rested, .metIn(.hours(1)), "Rested in about 1 h"),
    (.rested, .metIn(.soon), "Rested soon"),
    (.rested, .wantsNow, "Ready for a nap"),
    (.rested, .steady, "Fine for today"),
  ])
  func theHintIsAFewWords(need: PetNeed, outlook: NeedOutlook, hint: String) {
    #expect(need.hint(outlook) == hint)
  }

  @Test func noHintOutgrowsItsTile() {
    let outlooks: [NeedOutlook] = [
      .wantsNow, .lowIn(.soon), .lowIn(.hours(24)), .metIn(.soon), .metIn(.hours(24)), .steady,
    ]
    for need in PetNeed.allCases {
      for outlook in outlooks { #expect(need.hint(outlook).count <= 22) }
    }
  }
}
