import Foundation
import Testing

@testable import Labs

@Suite struct NextVisitTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func date(_ month: Int, _ day: Int, _ hour: Int = 15) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .now
  }

  private func visit(on day: Date, setOn: Date) -> NextVisit {
    NextVisit(day: day, setOn: setOn, calendar: calendar)
  }

  @Test func theCountdownCountsWholeCalendarDays() {
    let v = visit(on: date(11, 20, 9), setOn: date(11, 2))
    #expect(v.daysLeft(now: date(11, 2, 23), calendar: calendar) == 18)
    #expect(v.daysLeft(now: date(11, 20, 23), calendar: calendar) == 0)
    #expect(v.daysLeft(now: date(11, 21, 1), calendar: calendar) == -1)
  }

  @Test func theSuitcaseStartsEmptyAndIsFullOnTheDay() {
    let v = visit(on: date(11, 12), setOn: date(11, 2))
    #expect(v.packed(now: date(11, 2), calendar: calendar) == 0)
    #expect(v.packed(now: date(11, 12), calendar: calendar) == NextVisit.compartments)
  }

  @Test func theSuitcaseFillsAsTheDayNears() {
    let v = visit(on: date(11, 12), setOn: date(11, 2))
    let steps = (2...12).map { v.packed(now: date(11, $0), calendar: calendar) }
    #expect(steps == steps.sorted())
    #expect(Set(steps).count > 3)
    #expect(v.packed(now: date(11, 7), calendar: calendar) == 2)
  }

  @Test func aVisitSetForTomorrowHasOneStepToGo() {
    let v = visit(on: date(11, 3), setOn: date(11, 2))
    #expect(v.packed(now: date(11, 2), calendar: calendar) == 0)
    #expect(v.packed(now: date(11, 3), calendar: calendar) == NextVisit.compartments)
  }

  @Test func theSuitcaseIsPutAwayTheDayAfter() {
    let v = visit(on: date(11, 12), setOn: date(11, 2))
    #expect(v.isShown(now: date(11, 12, 23), calendar: calendar))
    #expect(!v.isShown(now: date(11, 13, 0), calendar: calendar))
  }

  @MainActor @Test func theStoreKeepsTheVisitAndClearsIt() {
    let defaults = UserDefaults(suiteName: "visit-\(UUID().uuidString)") ?? .standard
    let store = NextVisitStore(defaults: defaults)
    store.set(day: date(12, 24), now: date(11, 2), calendar: calendar)
    #expect(NextVisitStore(defaults: defaults).visit == store.visit)
    store.clear()
    #expect(NextVisitStore(defaults: defaults).visit == nil)
  }
}
