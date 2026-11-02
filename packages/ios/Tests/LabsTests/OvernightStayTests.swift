import FeatureInbox
import Foundation
import Testing

@testable import Labs

@Suite struct OvernightStayTests {
  private func note(_ direction: NoteRecord.Direction, minutes: Double) -> NoteRecord {
    NoteRecord(
      direction: direction, date: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60),
      strokes: [])
  }

  @Test func withoutNotesTheCatIsHome() {
    #expect(OvernightStay.place(after: []) == .here)
  }

  @Test func theCatStaysWithWhoeverGotTheLastNote() {
    let sent = note(.sent, minutes: 5)
    #expect(
      OvernightStay.place(after: [note(.received, minutes: 1), sent])
        == .withPartner(since: sent.date))
  }

  @Test func aNoteComingBackBringsTheCatBack() {
    #expect(
      OvernightStay.place(after: [note(.sent, minutes: 1), note(.received, minutes: 2)]) == .here)
  }

  @Test func theOrderOfTheListDoesNotMatter() {
    let notes = [note(.sent, minutes: 9), note(.received, minutes: 2), note(.received, minutes: 4)]
    #expect(OvernightStay.place(after: notes) == OvernightStay.place(after: notes.reversed()))
    #expect(OvernightStay.place(after: notes).isAway)
  }

  @Test func severalSentNotesKeepTheCatAwayFromTheFirst() {
    let latest = note(.sent, minutes: 8)
    let place = OvernightStay.place(after: [note(.sent, minutes: 3), latest])
    #expect(place == .withPartner(since: latest.date))
  }
}
