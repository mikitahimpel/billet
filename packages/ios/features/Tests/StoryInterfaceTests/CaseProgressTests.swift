import Foundation
import Testing

@testable import StoryInterface

@Suite struct ClueSplitTests {
  @Test(arguments: 0..<5) func eachPartnerSeesADifferentHalfAndTogetherTheyHaveBoth(beat: Int)
    throws
  {
    let episode = try EpisodeCatalog.load("fish-plush")
    let one = ClueSplit.half(of: episode.beats[beat], at: beat, side: .first)
    let two = ClueSplit.half(of: episode.beats[beat], at: beat, side: .second)
    #expect(one != two)
    #expect(Set([one.text, two.text]) == Set(episode.beats[beat].halves.map(\.text)))
  }

  @Test func neitherPartnerAlwaysHoldsTheFirstHalf() {
    let first = (0..<5).map { ClueSplit.halfIndex(of: .first, beat: $0) }
    #expect(Set(first) == [0, 1])
  }

  @Test func sidesFollowAccountIDsOnBothPhones() {
    #expect(Side(viewer: "a1", partner: "b2") == .first)
    #expect(Side(viewer: "b2", partner: "a1") == .second)
    #expect(Side.first.other == .second)
  }
}

@Suite struct CaseProgressTests {
  let episode = try! EpisodeCatalog.load("fish-plush")
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
  let day0 = Date(timeIntervalSince1970: Double(1_799_971_200 + 10 * 3600))

  func at(_ days: Int, hours: Int = 0) -> Date {
    day0.addingTimeInterval(Double(days * 86_400 + hours * 3600))
  }

  func found(_ beat: Int, _ when: Date) -> CaseMark {
    CaseMark(episode: "fish-plush", kind: .found, ref: episode.beats[beat].id, at: when)
  }

  func progress(mine: [CaseMark] = [], partner: [CaseMark] = [], now: Date) -> CaseProgress {
    CaseProgress(episode: episode, mine: mine, partner: partner, now: now, calendar: calendar)
  }

  @Test func aFreshCaseOpensTheFirstBeatAndNothingElse() {
    let state = progress(now: at(0))
    #expect(state.beats == [.waiting(partnerLooked: false)] + Array(repeating: .notYet, count: 4))
    #expect(state.stage == .clues(next: 0))
  }

  @Test func aBeatShowsWhetherThePartnerLooked() {
    let state = progress(partner: [found(0, at(0))], now: at(0))
    #expect(state.beats[0] == .waiting(partnerLooked: true))
    let mine = progress(mine: [found(0, at(0))], now: at(0))
    #expect(mine.beats[0] == .looked(partnerLooked: false))
  }

  @Test func theNextBeatOpensOnTheDayAfterBothFound() {
    let marks = [found(0, at(0))]
    let sameDay = progress(mine: marks, partner: marks, now: at(0, hours: 12))
    #expect(sameDay.beats[0] == .compared)
    #expect(sameDay.beats[1] == .notYet)
    #expect(sameDay.opensOn == calendar.startOfDay(for: at(1)))
    let nextDay = progress(mine: marks, partner: marks, now: at(1, hours: 0))
    #expect(nextDay.beats[1] == .waiting(partnerLooked: false))
    #expect(nextDay.opensOn == nil)
  }

  @Test func theSlowerPartnerSetsThePaceAndNothingEverExpires() {
    let mine = [found(0, at(0))]
    let partner = [found(0, at(5))]
    #expect(progress(mine: mine, partner: partner, now: at(5, hours: 1)).beats[1] == .notYet)
    #expect(
      progress(mine: mine, partner: partner, now: at(6)).beats[1] == .waiting(partnerLooked: false))
    #expect(
      progress(mine: mine, partner: partner, now: at(400)).beats[1]
        == .waiting(partnerLooked: false))
  }

  private func everyBeat() -> [CaseMark] { (0...4).map { found($0, at($0)) } }

  private func named(_ ref: String) -> CaseMark {
    CaseMark(episode: "fish-plush", kind: .named, ref: ref, at: at(9))
  }

  @Test func theChoiceStaysHiddenUntilBothAreIn() {
    let clues = everyBeat()
    #expect(progress(mine: clues, partner: clues, now: at(9)).stage == .naming)
    let state = progress(mine: clues + [named("crow")], partner: clues, now: at(9))
    #expect(state.stage == .named(choice: "crow"))
  }

  @Test(arguments: [
    ("crow", "crow", CaseProgress.Verdict.both), ("crow", "draft", .one),
    ("vacuum", "draft", .none),
  ])
  func theVerdictCountsWhoNamedTheCulprit(
    mine: String, theirs: String, verdict: CaseProgress.Verdict
  ) {
    let clues = everyBeat()
    let state = progress(
      mine: clues + [named(mine)], partner: clues + [named(theirs)], now: at(9))
    #expect(state.stage == .readyToTell(verdict: verdict))
    let told = CaseMark(episode: "fish-plush", kind: .found, ref: Episode.endingRef, at: at(9))
    let after = progress(
      mine: clues + [named(mine), told], partner: clues + [named(theirs)], now: at(9))
    #expect(after.stage == .told(verdict: verdict))
    #expect(after.isSolved)
  }

  @Test func marksOfAnotherEpisodeCountForNothing() {
    let other = CaseMark(episode: "other", kind: .found, ref: "empty-basket", at: at(0))
    let state = progress(mine: [other], partner: [other], now: at(0))
    #expect(state.beats[0] == .waiting(partnerLooked: false))
  }
}
