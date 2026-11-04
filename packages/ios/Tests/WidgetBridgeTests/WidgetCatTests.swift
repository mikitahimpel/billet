import Delivery
import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite struct WidgetCatTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func date(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 11, day: 3, hour: hour, minute: minute))!
  }

  private func snapshot(
    _ treat: WidgetSnapshot.Treat, at now: Date, life: WidgetLife? = nil
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      catName: "Mochi", treat: treat, treatDay: TreatDay.key(for: now, calendar: calendar),
      life: life, updatedAt: now)
  }

  @Test(arguments: [
    (WidgetSnapshot.Treat.neither, 12, WidgetCat.Pose.waiting, WidgetCare.treat),
    (.waitingOnMe, 12, .waiting, .treat),
    (.waitingOnPartner, 12, .sitting, .pet),
    (.fed, 12, .sitting, .pet),
    (.fed, 23, .sleeping, .pet),
    (.neither, 3, .sleeping, .treat),
  ])
  func withoutNeedsTheTreatAndTheHourDecide(
    _ treat: WidgetSnapshot.Treat, _ hour: Int, _ pose: WidgetCat.Pose, _ care: WidgetCare
  ) {
    let cat = WidgetCat(
      snapshot: snapshot(treat, at: date(hour)), now: date(hour), calendar: calendar)
    #expect(cat.pose == pose)
    #expect(cat.care == care)
    #expect(cat.thought == nil)
  }

  @Test func aTreatGivenYesterdayIsDueAgainToday() {
    let yesterday = snapshot(.fed, at: date(12).addingTimeInterval(-86_400))
    let cat = WidgetCat(snapshot: yesterday, now: date(12), calendar: calendar)
    #expect(cat.care == .treat)
  }

  @Test func withNeedsTheButtonOffersATreatOnlyWhenTheCatIsHungry() {
    let born = date(8)
    let life = WidgetLife(
      events: [LifeEvent(kind: .pet, by: "a", at: born)],
      context: LifeContext(partners: ["a", "b"], utcOffset: 0, born: born))
    for hour in stride(from: 0, through: 60, by: 3) {
      let now = born.addingTimeInterval(Double(hour) * 3600)
      let snap = snapshot(.fed, at: now, life: life)
      let cat = WidgetCat(snapshot: snap, now: now, calendar: calendar)
      let state = life.state(at: now)
      #expect(cat.thought == life.thought(at: now))
      #expect((cat.care == .treat) == (cat.thought == .full), "hour \(hour)")
      if state.asleep {
        #expect(cat.pose == .sleeping)
      } else {
        #expect(cat.pose == (cat.thought == nil ? .sitting : .waiting), "hour \(hour)")
      }
    }
  }

  @Test func aTreatIsTheDaysTreatWhileItIsMineToGiveAndFoodEitherWay() {
    #expect(WidgetCare.pet.plays(treat: .neither) == [.pet])
    #expect(WidgetCare.treat.plays(treat: .neither) == [.treat, .feed])
    #expect(WidgetCare.treat.plays(treat: .waitingOnMe) == [.treat, .feed])
    #expect(WidgetCare.treat.plays(treat: .waitingOnPartner) == [.feed])
    #expect(WidgetCare.treat.plays(treat: .fed) == [.feed])
    #expect(WidgetCare.pet.action == .pet)
    #expect(WidgetCare.treat.action == .treat)
  }

  @Test func theButtonRestsTenMinutesAfterACare() {
    let tapped = CatCareRecord(care: .pet, at: date(12))
    let snap = snapshot(.fed, at: date(12))
    #expect(
      CatCareRequest.decide(snapshot: snap, last: nil, now: date(12), calendar: calendar)
        == .success(.pet))
    #expect(
      CatCareRequest.decide(snapshot: snap, last: tapped, now: date(12, 9), calendar: calendar)
        == .failure(.tooSoon(until: date(12, 10))))
    #expect(
      CatCareRequest.decide(snapshot: snap, last: tapped, now: date(12, 10), calendar: calendar)
        == .success(.pet))
    #expect(CatCareRequest.cooling(last: tapped, now: date(12, 5)) == date(12, 10))
    #expect(CatCareRequest.cooling(last: tapped, now: date(12, 10)) == nil)
  }

  @Test func aClockSetBackDoesNotLockTheButton() {
    let future = CatCareRecord(care: .pet, at: date(18))
    #expect(CatCareRequest.cooling(last: future, now: date(12)) == nil)
  }

  @Test func nothingHappensBeforeTheAppHasPublishedThePair() {
    #expect(
      CatCareRequest.decide(snapshot: nil, last: nil, now: date(12), calendar: calendar)
        == .failure(.notPaired))
  }

  @Test func aTreatFromTheWidgetShowsAtOnce() {
    let now = date(12)
    let life = WidgetLife(
      events: [], context: LifeContext(partners: ["me", "you"], utcOffset: 0, born: date(8)))
    let ids = (UUID(), UUID())
    let applied = CatCareRequest.applied(
      [(ids.0, .treat), (ids.1, .feed)], by: "me", to: snapshot(.waitingOnMe, at: now, life: life),
      now: now, calendar: calendar)
    #expect(applied.treat == .fed)
    #expect(applied.streak == 1)
    #expect(applied.life?.events == [LifeEvent(id: ids.1, kind: .feed, by: "me", at: now)])
    let first = CatCareRequest.applied(
      [(ids.0, .treat)], by: "me", to: snapshot(.neither, at: now), now: now, calendar: calendar)
    #expect(first.treat == .waitingOnPartner)
    #expect(first.streak == 0)
  }

  @Test func aPetWithoutTheNeedsOnChangesNothingButIsNotLost() {
    let now = date(12)
    let before = snapshot(.fed, at: now)
    let applied = CatCareRequest.applied(
      [(UUID(), .pet)], by: "me", to: before, now: now, calendar: calendar)
    #expect(applied == before)
  }

  @Test func theLastCareSurvivesTheStore() throws {
    let store = CatCareStore(
      storage: .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    )
    #expect(store.load() == nil)
    let record = CatCareRecord(care: .treat, at: date(12))
    try store.save(record)
    #expect(store.load() == record)
  }

  @Test func thePartnersCareIsTheirNewestPetOrMeal() {
    let events = [
      LifeEvent(kind: .pet, by: "you", at: date(9)),
      LifeEvent(kind: .feed, by: "you", at: date(10)),
      LifeEvent(kind: .note, by: "you", at: date(11)),
      LifeEvent(kind: .pet, by: "me", at: date(12)),
    ]
    let care = PartnerCare.latest(in: events, me: "me")
    #expect(care == PartnerCare(care: .treat, at: date(10)))
    #expect(care?.line(cat: "Mochi") == "Your partner fed Mochi")
    #expect(PartnerCare(care: .pet, at: date(9)).line(cat: nil) == "Your partner petted the cat")
    #expect(PartnerCare.latest(in: Array(events.suffix(1)), me: "me") == nil)
    #expect(care?.isFresh(at: date(21)) == true)
    #expect(care?.isFresh(at: date(23)) == false)
  }

  @Test func theRoomGetsPlainPlayFramesAtItsPlaysPath() throws {
    let room = DemoRoom(code: "ABCDEFGH23", device: "11111111-1111-4111-8111-111111111111")
    #expect(
      room.playsURL(host: "example.test")?.absoluteString
        == "https://example.test/demo/rooms/ABCDEFGH23/plays?device=11111111-1111-4111-8111-111111111111"
    )
    #expect(room.playsURL(host: "127.0.0.1:8787")?.scheme == "http")
    let id = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    let frame = RoomPlay(id: id, kind: "pet", at: "2026-11-03T12:00:00+01:00")
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode([frame]))
    let first = try #require((json as? [[String: String]])?.first)
    #expect(
      first == [
        "type": "play", "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "kind": "pet",
        "at": "2026-11-03T12:00:00+01:00",
      ])
  }

  @Test func theHostIsSharedWithTheWidgetAndForgottenWhenEmpty() throws {
    let defaults = try #require(UserDefaults(suiteName: "widget-cat-\(UUID().uuidString)"))
    #expect(DemoRoom.host(in: defaults) == nil)
    DemoRoom.saveHost("example.test", in: defaults)
    #expect(DemoRoom.host(in: defaults) == "example.test")
    DemoRoom.saveHost("", in: defaults)
    #expect(DemoRoom.host(in: defaults) == nil)
  }
}
