import Foundation
import Testing

@testable import Pet

@Suite("Cat diary")
struct CatDiaryTests {
  /// 04:00 UTC on a day well after 1970.
  let dawn = 20_000.0 * 86400 + 4 * 3600

  @Test func aStretchIsSharedOutOverTheHoursItCrosses() {
    var diary = CatDiary()
    diary.spent(.rest, from: dawn + 1800, to: dawn + 3 * 3600 + 600, utcOffset: 0)
    #expect(diary.hours[4]?[.rest] == 1800)
    #expect(diary.hours[5]?[.rest] == 3600)
    #expect(diary.hours[6]?[.rest] == 3600)
    #expect(diary.hours[7]?[.rest] == 600)
    #expect(diary.hours.count == 4)
  }

  @Test func theHourIsThePairsOwn() {
    var diary = CatDiary()
    // 04:10 UTC is 09:40 at +05:30, so 20 minutes fall in hour 9 and 10 in hour 10.
    diary.spent(.play, from: dawn + 600, to: dawn + 2400, utcOffset: 19800)
    #expect(diary.hours[9]?[.play] == 1200)
    #expect(diary.hours[10]?[.play] == 600)
    #expect(CatDiary.hour(at: 1800, utcOffset: -3600) == 23)
  }

  @Test(arguments: [(10.0, 10.0), (10.0, 5.0), (Double.nan, 10.0), (0.0, Double.infinity)])
  func aStretchWithNoLengthIsNotWritten(start: Double, end: Double) {
    var diary = CatDiary()
    diary.spent(.play, from: start, to: end, utcOffset: 0)
    #expect(diary.hours.isEmpty)
  }
}

@Suite("Cat day story")
struct CatDayStoryTests {
  let dawn = 20_000.0 * 86400 + 4 * 3600

  private func at(_ hour: Double) -> Double { dawn + (hour - 4) * 3600 }

  private func event(_ kind: LifeEvent.Kind, _ hour: Double) -> LifeEvent {
    LifeEvent(kind: kind, by: "a", at: Date(timeIntervalSince1970: at(hour)))
  }

  private func story(_ diary: CatDiary, _ events: [LifeEvent] = [], until hour: Double)
    -> [CatDayMoment]
  {
    CatDayStory.moments(diary: diary, events: events, dayStart: dawn, now: at(hour), utcOffset: 0)
  }

  @Test func aNightsSleepIsOneMomentAndANapAnother() {
    var diary = CatDiary()
    diary.spent(.rest, from: at(4), to: at(7.5), utcOffset: 0)
    diary.spent(.watch, from: at(9), to: at(9.5), utcOffset: 0)
    diary.spent(.rest, from: at(13), to: at(15), utcOffset: 0)
    let moments = story(diary, until: 16)
    #expect(moments.map(\.kind) == [.slept, .watched, .napped])
    #expect(moments.map(\.at) == [at(4), at(9), at(13)])
    #expect(moments.map(\.until) == [at(8), at(10), at(15)])
    #expect(moments.allSatisfy { !$0.exact })
  }

  @Test func whatTheCoupleDidKeepsItsOwnMinuteAndReplacesTheHour() {
    var diary = CatDiary()
    diary.spent(.eat, from: at(8), to: at(8.3), utcOffset: 0)
    diary.spent(.play, from: at(18), to: at(18.5), utcOffset: 0)
    let moments = story(diary, [event(.feed, 8.2), event(.play, 18.1)], until: 20)
    #expect(moments.map(\.kind) == [.ate, .playedTogether])
    #expect(moments.map(\.at) == [at(8.2), at(18.1)])
    #expect(moments.allSatisfy { $0.exact })
  }

  @Test func petsCloseTogetherAreOneMoment() {
    let events = [event(.pet, 10), event(.pet, 10.2), event(.pet, 10.6), event(.pet, 12)]
    #expect(story(CatDiary(), events, until: 13).map(\.at) == [at(10), at(12)])
  }

  @Test func sittingAboutAShortSpellAndAReflexAreNotTold() {
    var diary = CatDiary()
    diary.spent(.idle, from: at(9), to: at(10), utcOffset: 0)
    diary.spent(.react, from: at(10), to: at(10.5), utcOffset: 0)
    diary.spent(.groom, from: at(11), to: at(11) + CatDayStory.hourShare - 1, utcOffset: 0)
    #expect(story(diary, until: 12).isEmpty)
  }

  @Test func eventsOfOtherDaysAndOfNoInterestAreLeftOut() {
    let events = [
      event(.feed, 3.9), event(.feed, 30), event(.sleep, 10), event(.shoo, 10),
      event(.overfeed, 10),
    ]
    #expect(story(CatDiary(), events, until: 12).isEmpty)
  }

  @Test func onlyTheLatestMomentsAreKept() {
    let events = (0..<12).map { event(.note, 5 + Double($0)) }
    let moments = story(CatDiary(), events, until: 20)
    #expect(moments.count == CatDayStory.limit)
    #expect(moments.last?.at == at(16))
    #expect(moments.map(\.at) == moments.map(\.at).sorted())
  }

  @Test(arguments: [(0.0, 0.0), (10.0, 5.0), (Double.nan, 10.0), (0.0, Double.infinity)])
  func aDayThatHasNotBegunHasNoStory(dayStart: Double, now: Double) {
    var diary = CatDiary()
    diary.spent(.rest, from: 0, to: 7200, utcOffset: 0)
    #expect(
      CatDayStory.moments(diary: diary, events: [], dayStart: dayStart, now: now, utcOffset: 0)
        .isEmpty)
  }

  @Test func aMomentUnderWayEndsNow() {
    var diary = CatDiary()
    diary.spent(.rest, from: at(13), to: at(13.5), utcOffset: 0)
    #expect(story(diary, until: 13.5).map(\.until) == [at(13.5)])
  }

  @Test func aTieFallsToTheSameGroupEveryTime() {
    let hour: [CatActivityGroup: Double] = [.watch: 900, .explore: 900, .groom: 900]
    for _ in 0..<20 { #expect(CatDayStory.kind(of: hour, hour: 12) == .explored) }
  }

  @Test func theBrainTellsTheSameDayHoweverItGotThere() {
    let context = LifeContext(
      partners: ["a", "b"], utcOffset: 3600, born: Date(timeIntervalSince1970: dawn - 5 * 86400))
    let events = [event(.feed, 8.5), event(.play, 12.25)]
    let room = RoomAffordances([
      RoomAffordance(id: "window", kind: .window), RoomAffordance(id: "bed", kind: .bed),
      RoomAffordance(id: "bowl", kind: .bowl),
    ])
    let now = at(17)
    var runner = CatBrainRunner(events: events, now: at(9), context: context, seed: 7, room: room)
    var t = at(9)
    while t < now {
      t += 601
      runner.advance(to: min(t, now))
    }
    let replayed = CatBrainRunner.replay(
      events: events, now: now, context: context, seed: 7, room: room)
    let moments = runner.brain.dayMoments(events: events)
    #expect(moments == replayed.dayMoments(events: events))
    #expect(!moments.isEmpty && moments.count <= CatDayStory.limit)
    // From the day's start, 04:00 at +01:00, to now. A group an event cuts short is not always
    // written, so a little of the day may be missing; none of it is counted twice.
    let total = runner.brain.today.hours.values.flatMap(\.values).reduce(0, +)
    let span = now - (dawn - 3600)
    #expect(total <= span + 1 && total > span * 0.98, "\(total) of \(span)")
  }
}

@Suite("About the cat")
struct CatAboutWordsTests {
  @Test func theTraitsThatSetHerApartComeFirst() {
    let cat = CatPersonality(
      curious: 0.9, lazy: 0.15, cuddly: 0.5, playful: 0.6, bold: 0.5, vocal: 0.45)
    let standouts = cat.standouts(2)
    #expect(standouts.map(\.trait) == [.curious, .lazy])
    #expect(standouts.map(\.high) == [true, false])
    #expect(cat.standouts(0).isEmpty)
    #expect(cat.standouts(-1).isEmpty)
    #expect(CatPersonality.even.standouts(9).count == CatPersonality.Trait.allCases.count)
  }

  @Test func everyTraitHasAName() {
    let titles = CatPersonality.Trait.allCases.map(\.title)
    #expect(Set(titles).count == titles.count)
    #expect(titles.allSatisfy { !$0.isEmpty && $0.count <= 8 })
  }

  @Test func aPlaceSheOnlyPassesIsNoFavouriteSpot() {
    for kind in [RoomAffordance.Kind.bowl, .smallItem, .door, .toy] {
      #expect(kind.spotName(for: .they) == nil)
    }
    let named = RoomAffordance.Kind.allCases.compactMap { $0.spotName(for: .they) }
    #expect(named.count == RoomAffordance.Kind.allCases.count - 4)
    #expect(named.allSatisfy { $0.count <= 20 })
  }
}
