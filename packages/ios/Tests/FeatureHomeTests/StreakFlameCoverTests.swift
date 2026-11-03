import FeatureInbox
import Foundation
import Pet
import Testing

@testable import FeatureHome

@Suite("Streak flame on Home")
struct StreakFlameCoverTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return calendar
  }

  private let now = Date(timeIntervalSince1970: 1_793_800_000)

  private func note(_ direction: NoteRecord.Direction, hoursAgo: Double) -> NoteRecord {
    NoteRecord(direction: direction, date: now.addingTimeInterval(-hoursAgo * 3600), strokes: [])
  }

  @Test func todaysNotesSayWhoAdded() {
    let today = FlameToday.contributions(
      notes: [note(.received, hoursAgo: 1)], treat: .neither, now: now, calendar: calendar)
    #expect(today == FlameContributions(mine: false, theirs: true))
  }

  @Test func yesterdaysNotesDoNotCount() {
    let today = FlameToday.contributions(
      notes: [note(.sent, hoursAgo: 30), note(.received, hoursAgo: 40)], treat: .neither, now: now,
      calendar: calendar)
    #expect(today == FlameContributions())
  }

  @Test func todaysTreatCountsForWhoeverGaveIt() {
    #expect(
      FlameToday.contributions(notes: [], treat: .fed, now: now, calendar: calendar)
        == FlameContributions(mine: true, theirs: true))
    #expect(
      FlameToday.contributions(notes: [], treat: .waitingOnPartner, now: now, calendar: calendar)
        == FlameContributions(mine: true, theirs: false))
  }

  @Test func theStoreRemembersEachVisitOnce() throws {
    let suite = "flame-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = FlameMemoryStore.key(fakePartner: false)
    let first = FlameMemoryStore.visit(streak: 7, newestNote: nil, key: key, defaults: defaults)
    #expect(first.milestone == .steady)
    let again = FlameMemoryStore.visit(streak: 7, newestNote: nil, key: key, defaults: defaults)
    #expect(again == .quiet)
    _ = FlameMemoryStore.visit(streak: 0, newestNote: nil, key: key, defaults: defaults)
    let back = FlameMemoryStore.visit(streak: 1, newestNote: nil, key: key, defaults: defaults)
    #expect(back.rekindled)
  }

  @Test func theFakePartnerKeepsItsOwnMemory() {
    #expect(FlameMemoryStore.key(fakePartner: true) != FlameMemoryStore.key(fakePartner: false))
  }

  @Test func theEmberLineNeverBlames() {
    let line = FlameCopy.ember.lowercased()
    for word in ["lost", "broke", "died", "dead", "miss", "fail", "streak"] {
      #expect(!line.contains(word))
    }
  }
}
