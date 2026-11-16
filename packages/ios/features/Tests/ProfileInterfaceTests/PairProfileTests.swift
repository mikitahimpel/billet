import Foundation
import ProfileInterface
import Testing

@Suite struct PairProfileTests {
  let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  func paired(names: [String: String]? = nil, chosen: Bool? = nil) -> Couple {
    var couple = Couple(
      partners: ["L", "M"], togetherSince: day("2026-11-15"), viewer: "L", names: names,
      pair: PairMembers(pairID: "p", users: ["L": "me", "M": "you"]))
    couple.togetherSinceChosen = chosen
    return couple
  }

  func day(_ text: String) -> Date { PairProfile.date(localDay: text, calendar: utc)! }

  @Test func thePartnersNameFromTheServerFillsTheirMonogram() {
    let (couple, pushes) = paired(names: ["L": "Alex", "M": ""]).merging(
      PairProfile(myName: "Alex", partnerName: "Sam"), calendar: utc)
    #expect(couple.name(of: "M") == "Sam")
    #expect(!couple.isUnknownPartner("M"))
    #expect(pushes.isEmpty)
  }

  @Test func aPartnerNameTypedHereStaysWhileTheServerHasNone() {
    let (couple, _) = paired(names: ["M": "Sammy"]).merging(PairProfile(), calendar: utc)
    #expect(couple.name(of: "M") == "Sammy")
  }

  @Test func theHoldersOwnNameIsPushedWhenTheServerLacksOrDiffersFromIt() {
    #expect(
      paired(names: ["L": " Alex "]).merging(PairProfile(), calendar: utc).1 == [.name("Alex")])
    #expect(
      paired(names: ["L": "Alex"]).merging(PairProfile(myName: "Al"), calendar: utc).1
        == [.name("Alex")])
  }

  @Test func withNoNameHereTheServersOwnIsKept() {
    let (couple, pushes) = paired().merging(PairProfile(myName: "Alex"), calendar: utc)
    #expect(couple.name(of: "L") == "Alex")
    #expect(pushes.isEmpty)
  }

  @Test func thePairsDayWinsOverEitherPhonesOwn() {
    let (couple, pushes) = paired(chosen: true).merging(
      PairProfile(togetherSince: day("2024-02-14"), pairedAt: day("2026-11-16")), calendar: utc)
    #expect(couple.togetherSince == day("2024-02-14"))
    #expect(couple.togetherSinceChosen == nil)
    #expect(pushes.isEmpty)
  }

  @Test func aDayChosenBeforePairingIsOfferedOnlyIfThePairHasNone() {
    let (couple, pushes) = paired(chosen: true).merging(
      PairProfile(pairedAt: day("2026-11-16")), calendar: utc)
    #expect(couple.togetherSince == day("2026-11-15"))
    #expect(pushes == [.day(day("2026-11-15"), ifUnset: true)])
  }

  @Test func withoutAChosenDayBothPhonesCountFromThePairing() {
    let (couple, pushes) = paired().merging(
      PairProfile(pairedAt: day("2026-11-16").addingTimeInterval(3600)), calendar: utc)
    #expect(couple.togetherSince == day("2026-11-16"))
    #expect(Couple.days(since: couple.togetherSince, on: day("2026-11-16")) == 1)
    #expect(pushes.isEmpty)
  }

  @Test func namesAreCutToWhatTheServerTakes() {
    #expect(PairProfile.displayName("  \n ") == nil)
    #expect(PairProfile.displayName("Al\u{7}ex") == "Alex")
    #expect(PairProfile.displayName(String(repeating: "é", count: 50))?.unicodeScalars.count == 40)
  }

  @Test func aLocalDayReadsBackAsTheSameDay() {
    #expect(PairProfile.localDay(day("2025-03-09"), calendar: utc) == "2025-03-09")
    #expect(PairProfile.date(localDay: "2025-3-9", calendar: utc) == nil)
  }
}
