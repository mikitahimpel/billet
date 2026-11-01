import Foundation
import Testing
import Wire

@testable import Labs

@Suite struct SealedBoxTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))
      ?? .now
  }

  private func sealed(at opens: Date, _ direction: SealedNote.Direction = .outgoing) -> SealedNote {
    SealedNote(strokes: [], opensAt: opens, direction: direction)
  }

  @Test func tomorrowMorningIsTheNextDaysEight() {
    #expect(SealedBox.tomorrowMorning(after: date(2, 21), calendar: calendar) == date(3, 8))
    #expect(SealedBox.tomorrowMorning(after: date(2, 7, 59), calendar: calendar) == date(3, 8))
    #expect(SealedBox.tomorrowMorning(after: date(2, 0, 30), calendar: calendar) == date(3, 8))
  }

  @Test func tomorrowMorningHoldsAcrossTheClocksChanging() {
    // Berlin moves its clocks on 25 October 2026.
    let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23)) ?? .now
    let morning = SealedBox.tomorrowMorning(after: late, calendar: calendar)
    #expect(
      calendar.dateComponents([.day, .hour, .minute], from: morning)
        == DateComponents(day: 25, hour: 8, minute: 0))
  }

  @Test func aNoteStaysSealedUntilItsTime() {
    var box = SealedBox()
    box.seal(sealed(at: date(3, 8)))
    #expect(box.release(at: date(3, 7, 59)).isEmpty)
    #expect(box.notes.count == 1)
  }

  @Test func aNoteOpensAtItsTimeAndLeavesTheBox() {
    var box = SealedBox()
    let note = sealed(at: date(3, 8))
    box.seal(note)
    #expect(box.release(at: date(3, 8)) == [note])
    #expect(box.notes.isEmpty)
    #expect(box.release(at: date(4, 8)).isEmpty)
  }

  @Test func onlyDueNotesOpenAndTheRestKeepWaiting() {
    var box = SealedBox()
    let early = sealed(at: date(3, 8))
    let late = sealed(at: date(5, 8), .incoming)
    box.seal(late)
    box.seal(early)
    #expect(box.release(at: date(4, 12)) == [early])
    #expect(box.waiting(.incoming) == [late])
    #expect(box.waiting(.outgoing).isEmpty)
  }

  @Test func sealingTheSameNoteAgainReplacesIt() {
    var box = SealedBox()
    let note = sealed(at: date(3, 8))
    box.seal(note)
    box.seal(SealedNote(id: note.id, strokes: [], opensAt: date(4, 8), direction: .outgoing))
    #expect(box.notes.count == 1)
    #expect(box.notes[0].opensAt == date(4, 8))
  }

  @Test func theBoxSurvivesEncoding() throws {
    var box = SealedBox()
    box.seal(
      SealedNote(
        strokes: [Stroke(color: "#112233", width: 0.01, points: [Point(x: 0.1, y: 0.2)])],
        opensAt: date(3, 8), direction: .incoming))
    #expect(try JSONDecoder().decode(SealedBox.self, from: JSONEncoder().encode(box)) == box)
  }

  @MainActor @Test func theStoreKeepsASealedNoteAcrossLaunches() {
    let defaults = UserDefaults(suiteName: "sealed-\(UUID().uuidString)") ?? .standard
    let note = sealed(at: date(3, 8))
    SealedBoxStore(defaults: defaults).seal(note)
    let again = SealedBoxStore(defaults: defaults)
    #expect(again.box.notes == [note])
    #expect(again.release(at: date(3, 9)) == [note])
    #expect(SealedBoxStore(defaults: defaults).box.notes.isEmpty)
  }
}
