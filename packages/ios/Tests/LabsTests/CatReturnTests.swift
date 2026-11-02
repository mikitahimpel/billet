import Foundation
import Testing

@testable import Labs

@Suite struct CatReturnTests {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func theCatStartsIdle() {
    #expect(CatReturn().phase == .idle)
    #expect(!CatReturn().isBack(now: start))
  }

  @Test func sendingSendsTheCatOut() {
    var trip = CatReturn()
    let note = UUID()
    trip.sent(note)
    #expect(trip.phase == .out(note: note))
    #expect(!trip.isBack(now: start))
  }

  @Test func openingTheCarriedNoteBringsTheCatBack() {
    var trip = CatReturn()
    let note = UUID()
    trip.sent(note)
    trip.opened(note, at: start)
    #expect(trip.phase == .back(note: note, at: start))
    #expect(trip.isBack(now: start.addingTimeInterval(60)))
  }

  @Test func anOlderNoteBeingOpenedLateChangesNothing() {
    var trip = CatReturn()
    let old = UUID()
    let newer = UUID()
    trip.sent(old)
    trip.sent(newer)
    trip.opened(old, at: start)
    #expect(trip.phase == .out(note: newer))
  }

  @Test func openingANoteTheCatDoesNotCarryChangesNothing() {
    var trip = CatReturn()
    trip.opened(UUID(), at: start)
    #expect(trip.phase == .idle)
  }

  @Test func theEmptySatchelIsShownForTwelveHoursOnly() {
    var trip = CatReturn()
    let note = UUID()
    trip.sent(note)
    trip.opened(note, at: start)
    #expect(trip.isBack(now: start.addingTimeInterval(CatReturn.showFor - 1)))
    #expect(!trip.isBack(now: start.addingTimeInterval(CatReturn.showFor)))
  }

  @Test func aNewNoteSendsTheCatOutAgain() {
    var trip = CatReturn()
    let first = UUID()
    trip.sent(first)
    trip.opened(first, at: start)
    let second = UUID()
    trip.sent(second)
    #expect(trip.phase == .out(note: second))
    #expect(!trip.isBack(now: start))
  }

  @Test func aClockBeforeTheOpeningDoesNotShowIt() {
    var trip = CatReturn()
    let note = UUID()
    trip.sent(note)
    trip.opened(note, at: start)
    #expect(!trip.isBack(now: start.addingTimeInterval(-5)))
  }
}
