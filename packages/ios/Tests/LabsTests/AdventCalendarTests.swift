import Foundation
import Testing
import Wire

@testable import Labs

@Suite struct AdventCalendarTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func date(_ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .now
  }

  private let ink = [
    Stroke(color: "#112233", width: 0.02, points: [Point(x: 0.2, y: 0.2), Point(x: 0.8, y: 0.8)])
  ]

  @Test func noDoorOpensBeforeDecember() {
    for number in AdventCalendar.doors {
      #expect(!AdventCalendar.isOpenable(number, on: date(11, 30), calendar: calendar))
    }
  }

  @Test func aDoorOpensFromItsOwnDayAndNotBefore() {
    #expect(AdventCalendar.isOpenable(1, on: date(12, 1), calendar: calendar))
    #expect(!AdventCalendar.isOpenable(2, on: date(12, 1), calendar: calendar))
    #expect(AdventCalendar.isOpenable(2, on: date(12, 2), calendar: calendar))
    #expect(AdventCalendar.isOpenable(24, on: date(12, 24), calendar: calendar))
    #expect(AdventCalendar.isOpenable(24, on: date(12, 31), calendar: calendar))
  }

  @Test func thereAreOnlyTwentyFourDoors() {
    #expect(!AdventCalendar.isOpenable(0, on: date(12, 31), calendar: calendar))
    #expect(!AdventCalendar.isOpenable(25, on: date(12, 31), calendar: calendar))
    var advent = AdventCalendar(year: 2026)
    let tooHigh = advent.fillForPartner(25, strokes: ink)
    #expect(!tooHigh)
    #expect(advent.filled.isEmpty)
  }

  @Test func todaysDoorIsTheDayOfDecemberUpToTheTwentyFourth() {
    #expect(AdventCalendar.todaysDoor(on: date(12, 7), calendar: calendar) == 7)
    #expect(AdventCalendar.todaysDoor(on: date(12, 25), calendar: calendar) == nil)
    #expect(AdventCalendar.todaysDoor(on: date(11, 7), calendar: calendar) == nil)
  }

  @Test func aDoorIsFilledOnceAndNeverWithNothing() {
    var advent = AdventCalendar(year: 2026)
    let empty = advent.fillForPartner(3, strokes: [])
    let first = advent.fillForPartner(3, strokes: ink)
    let second = advent.fillForPartner(3, strokes: ink + ink)
    #expect(!empty)
    #expect(first)
    #expect(!second)
    #expect(advent.door(3)?.strokes == ink)
    #expect(advent.door(3)?.maker == .me)
  }

  @Test func thePartnersDoorNeverReplacesOneIFilled() {
    var advent = AdventCalendar(year: 2026)
    advent.fillForPartner(5, strokes: ink)
    advent.partnerFilled(5, strokes: [])
    #expect(advent.door(5)?.maker == .me)
  }

  @Test func aPartnersDoorOpensOnItsDayAndGivesItsDrawing() {
    var advent = AdventCalendar(year: 2026)
    advent.partnerFilled(4, strokes: ink)
    let early = advent.open(4, on: date(12, 3), calendar: calendar)
    #expect(early == nil)
    #expect(advent.door(4)?.opened == false)
    let onTheDay = advent.open(4, on: date(12, 4), calendar: calendar)
    #expect(onTheDay == ink)
    #expect(advent.door(4)?.opened == true)
  }

  @Test func aDoorIFilledIsNotMineToOpen() {
    var advent = AdventCalendar(year: 2026)
    advent.fillForPartner(4, strokes: ink)
    let opened = advent.open(4, on: date(12, 24), calendar: calendar)
    #expect(opened == nil)
  }

  @MainActor @Test func theStoreFillsTheDoorTheCanvasWasOpenedForAndForgetsIt() {
    let defaults = UserDefaults(suiteName: "advent-\(UUID().uuidString)") ?? .standard
    let store = AdventStore(year: 2026, defaults: defaults)
    #expect(store.finishDrawing(ink) == nil)
    store.drawingFor = 9
    #expect(store.finishDrawing(ink) == 9)
    #expect(store.drawingFor == nil)
    #expect(AdventStore(year: 2026, defaults: defaults).calendar.door(9)?.strokes == ink)
  }

  @MainActor @Test func aCalendarFromAnotherYearStartsOver() {
    let defaults = UserDefaults(suiteName: "advent-\(UUID().uuidString)") ?? .standard
    let store = AdventStore(year: 2026, defaults: defaults)
    store.partnerFilled(2, strokes: ink)
    #expect(AdventStore(year: 2027, defaults: defaults).calendar.filled.isEmpty)
    #expect(AdventStore(year: 2026, defaults: defaults).calendar.filled.count == 1)
  }
}
