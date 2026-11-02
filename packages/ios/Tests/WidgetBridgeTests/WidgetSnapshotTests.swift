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

@Suite("Widget life")
struct WidgetLifeTests {
  private static let noon = Date(timeIntervalSince1970: 1_793_620_800)
  private static let context = LifeContext(partners: ["a", "b"], utcOffset: 0, born: noon)

  private func snapshot(_ events: [LifeEvent]) -> WidgetSnapshot {
    WidgetSnapshot(
      treatDay: "2026-11-02", life: WidgetLife(events: events, context: Self.context),
      updatedAt: Self.noon)
  }

  @Test func theWidgetWorksOutTheSameStateAsThePhone() {
    let events = [
      LifeEvent(kind: .feed, by: "a", at: Self.noon), LifeEvent(kind: .pet, by: "b", at: Self.noon),
    ]
    let later = Self.noon.addingTimeInterval(3 * 3600)
    let phone = PetLife.state(events: events, now: later, context: Self.context)
    #expect(snapshot(events).life?.state(at: later) == phone)
  }

  @Test func moodFollowsTheNeedsWhenTheLifeIsOn() throws {
    let calendar = Calendar(identifier: .gregorian)
    let fresh = CatMood(snapshot: snapshot([]), now: Self.noon, calendar: calendar)
    #expect(fresh == .happy)
    // Alone for a day and a half: hungry first, since Full falls fastest.
    let later = Self.noon.addingTimeInterval(36 * 3600)
    let alone = snapshot([LifeEvent(kind: .pet, by: "a", at: Self.noon)])
    let mood = CatMood(snapshot: alone, now: later, calendar: calendar)
    let state = try #require(alone.life?.state(at: later))
    if state.asleep {
      #expect(mood == .sleepy)
    } else {
      #expect([.hungry, .playful, .lonely].contains(mood))
      #expect(alone.life?.thought(at: later) != nil)
    }
  }

  @Test func aSnapshotWithoutALifeStillDecodes() throws {
    let old = Data(
      #"{"treat":"fed","treatDay":"2026-11-02","streak":1,"partnerHere":false,"updatedAt":0}"#.utf8)
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: old)
    #expect(snapshot.life == nil)
  }

  @Test func theLifeRoundTripsThroughTheAppGroupFile() throws {
    let original = snapshot([LifeEvent(kind: .note, by: "a", at: Self.noon)])
    let decoded = try JSONDecoder().decode(
      WidgetSnapshot.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
