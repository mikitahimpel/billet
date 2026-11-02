import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct WidgetSnapshotTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  private func snapshot(
    day: Int, hour: Int = 12, treat: WidgetSnapshot.Treat = .neither, streak: Int = 0,
    here: Bool = false
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      treat: treat, treatDay: TreatDay.key(for: date(day, hour), calendar: calendar),
      streak: streak, partnerHere: here, updatedAt: date(day, hour))
  }

  @Test func sameDayIsUnchanged() {
    let snap = snapshot(day: 10, treat: .waitingOnMe, streak: 4)
    let now = snap.current(now: date(10, 18), calendar: calendar)
    #expect(now.treat == .waitingOnMe)
    #expect(now.streak == 4)
  }

  @Test func nextDayClearsTheTreatAndKeepsAFinishedStreak() {
    let fed = snapshot(day: 10, treat: .fed, streak: 4).current(
      now: date(11, 8), calendar: calendar)
    #expect(fed.treat == .neither)
    #expect(fed.streak == 4)
    let open = snapshot(day: 10, treat: .waitingOnPartner, streak: 4)
      .current(now: date(11, 8), calendar: calendar)
    #expect(open.streak == 0)
  }

  @Test func twoMissedDaysEndTheStreak() {
    let snap = snapshot(day: 10, treat: .fed, streak: 4).current(
      now: date(12, 8), calendar: calendar)
    #expect(snap.streak == 0)
  }

  @Test func presenceFadesWhenTheAppStopsSayingIt() {
    let snap = snapshot(day: 10, here: true)
    #expect(snap.current(now: date(10, 12, 5), calendar: calendar).partnerHere)
    #expect(!snap.current(now: date(10, 12, 11), calendar: calendar).partnerHere)
  }

  @Test func daysTogetherCountsTheFirstDayAsOne() {
    var snap = snapshot(day: 10)
    #expect(snap.daysTogether(now: date(10, 12), calendar: calendar) == nil)
    snap.pairedSince = date(10, 22)
    #expect(snap.daysTogether(now: date(10, 23), calendar: calendar) == 1)
    #expect(snap.daysTogether(now: date(13, 1), calendar: calendar) == 4)
  }

  @Test func storeRoundTripsAndRemoves() throws {
    let store = WidgetSnapshotStore(
      storage: .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    )
    #expect(store.load() == nil)
    let snap = snapshot(day: 10, treat: .fed, streak: 2)
    try store.save(snap)
    #expect(store.load() == snap)
    store.remove()
    #expect(store.load() == nil)
  }

  @Test func treatStatusMapsOneToOne() {
    #expect(WidgetSnapshot.Treat(.neither) == .neither)
    #expect(WidgetSnapshot.Treat(.waitingOnPartner) == .waitingOnPartner)
    #expect(WidgetSnapshot.Treat(.waitingOnMe) == .waitingOnMe)
    #expect(WidgetSnapshot.Treat(.fed) == .fed)
  }

  @Test func moodFollowsNightPresenceThenTheTreat() {
    func mood(_ treat: WidgetSnapshot.Treat, here: Bool, hour: Int) -> CatMood {
      CatMood(
        snapshot: snapshot(day: 10, hour: hour, treat: treat, here: here), now: date(10, hour),
        calendar: calendar)
    }
    #expect(mood(.fed, here: true, hour: 23) == .sleepy)
    #expect(mood(.fed, here: true, hour: 3) == .sleepy)
    #expect(mood(.fed, here: true, hour: 12) == .curious)
    #expect(mood(.fed, here: false, hour: 12) == .happy)
    #expect(mood(.waitingOnMe, here: false, hour: 12) == .hungry)
    #expect(mood(.waitingOnPartner, here: false, hour: 12) == .waiting)
    #expect(mood(.neither, here: false, hour: 12) == .content)
    for mood in CatMood.allCases {
      #expect(!mood.title.isEmpty && !mood.symbol.isEmpty && !mood.line(name: nil).isEmpty)
    }
  }
}
