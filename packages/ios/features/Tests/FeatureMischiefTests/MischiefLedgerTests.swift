import Foundation
import MischiefInterface
import Testing
import Wire

@testable import FeatureMischief

struct MischiefLedgerTests {
  static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
  static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

  static func hid(
    _ id: String, by: String = "leo", spot: String = "basket", line: String? = nil, at: Date = t0
  )
    -> CatEntry
  {
    CatEntry(
      seq: 1, id: IdempotencyKey(id), by: UserId(by), at: ms(at),
      event: .mouseHidden(spot: spot, line: line))
  }

  static func found(
    _ id: String, of hidden: String, by: String = "mia", at: Date = t0.addingTimeInterval(60)
  )
    -> CatEntry
  {
    CatEntry(
      seq: 2, id: IdempotencyKey(id), by: UserId(by), at: ms(at),
      event: .mouseFound(hidden: IdempotencyKey(hidden), spot: "basket", tries: 2, seconds: 45))
  }

  @Test func aHideIsOpenForItsHiderUntilFound() {
    var ledger = MischiefLedger()
    let changed1 = ledger.apply(Self.hid("h1", line: "  boo "), now: Self.t0)
    #expect(changed1)
    let open = ledger.open(hiddenBy: "leo", now: Self.t0)
    #expect(open?.spot == .basket)
    #expect(open?.line == "boo")
    #expect(ledger.open(hiddenBy: "mia", now: Self.t0) == nil)
    let changed2 = ledger.apply(Self.found("f1", of: "h1"), now: Self.t0)
    #expect(changed2)
    #expect(ledger.open(hiddenBy: "leo", now: Self.t0) == nil)
    #expect(ledger.over(now: Self.t0).map(\.hide.id) == ["h1"])
  }

  @Test func theSameEntryTwiceChangesNothing() {
    var ledger = MischiefLedger()
    ledger.apply(Self.hid("h1"), now: Self.t0)
    let changed3 = ledger.apply(Self.hid("h1"), now: Self.t0)
    #expect(!changed3)
    ledger.apply(Self.found("f1", of: "h1"), now: Self.t0)
    let changed4 = ledger.apply(Self.found("f2", of: "h1"), now: Self.t0)
    #expect(!changed4)
  }

  @Test func aFindThatArrivesFirstWaitsForItsHide() {
    var ledger = MischiefLedger()
    ledger.apply(Self.found("f1", of: "h1"), now: Self.t0)
    #expect(ledger.over(now: Self.t0).isEmpty)
    ledger.apply(Self.hid("h1"), now: Self.t0)
    #expect(ledger.over(now: Self.t0).count == 1)
  }

  @Test func theHiderCannotFindTheirOwnMouse() {
    var ledger = MischiefLedger()
    ledger.apply(Self.hid("h1"), now: Self.t0)
    let changed5 = ledger.apply(Self.found("f1", of: "h1", by: "leo"), now: Self.t0)
    #expect(!changed5)
    #expect(ledger.open(hiddenBy: "leo", now: Self.t0) != nil)
  }

  @Test func hidingAgainReplacesTheEarlierMouse() {
    var ledger = MischiefLedger()
    ledger.apply(Self.hid("h1", spot: "sofa"), now: Self.t0)
    let later = Self.t0.addingTimeInterval(3600)
    ledger.apply(Self.hid("h2", spot: "crate", at: later), now: later)
    #expect(ledger.open(hiddenBy: "leo", now: later)?.id == "h2")
    #expect(ledger.over(now: later).isEmpty)
  }

  @Test func afterThreeDaysTheCatTurnsItUp() {
    var ledger = MischiefLedger()
    ledger.apply(Self.hid("h1"), now: Self.t0)
    let almost = Self.t0.addingTimeInterval(3 * 86_400 - 1)
    #expect(ledger.open(hiddenBy: "leo", now: almost) != nil)
    let after = Self.t0.addingTimeInterval(3 * 86_400)
    #expect(ledger.open(hiddenBy: "leo", now: after) == nil)
    let over = ledger.over(now: after)
    #expect(over.count == 1)
    #expect(over.first?.status == .turnedUp(after))
  }

  @Test func aMouseWaitsLongerThanTheJournalIsRead() {
    var ledger = MischiefLedger()
    ledger.apply(Self.hid("h1"), now: Self.t0)
    let later = Self.t0.addingTimeInterval(2.5 * 86_400)
    #expect(ledger.open(hiddenBy: "leo", now: later)?.id == "h1")
  }

  @Test func anUnknownSpotIsIgnored() {
    var ledger = MischiefLedger()
    let changed6 = ledger.apply(Self.hid("h1", spot: "moon"), now: Self.t0)
    #expect(!changed6)
  }

  @Test func otherJournalEventsAreIgnored() {
    var ledger = MischiefLedger()
    let entry = CatEntry(
      seq: 1, id: IdempotencyKey("p"), by: UserId("leo"), at: Self.ms(Self.t0), event: .petted)
    let changed7 = ledger.apply(entry, now: Self.t0)
    #expect(!changed7)
  }

  @Test func onlyTheLatestFinishedAreKept() {
    var ledger = MischiefLedger()
    for index in 0..<(MischiefLedger.keepOver + 5) {
      let at = Self.t0.addingTimeInterval(Double(index) * 100)
      ledger.apply(Self.hid("h\(index)", at: at), now: at)
      ledger.apply(Self.found("f\(index)", of: "h\(index)", at: at.addingTimeInterval(10)), now: at)
    }
    let now = Self.t0.addingTimeInterval(10_000)
    let kept = ledger.over(now: now, limit: .max)
    #expect(kept.count == MischiefLedger.keepOver)
    #expect(kept.first?.hide.id == "h\(MischiefLedger.keepOver + 4)")
  }

  @Test func theLedgerSurvivesBeingSaved() throws {
    var ledger = MischiefLedger()
    ledger.apply(Self.hid("h1", line: "hi"), now: Self.t0)
    ledger.apply(Self.found("f0", of: "h0"), now: Self.t0)
    let again = try JSONDecoder().decode(MischiefLedger.self, from: JSONEncoder().encode(ledger))
    #expect(again == ledger)
  }
}
