import Foundation
import Labs
import Pet
import Testing
import Wire

@testable import FeatureHome

@Suite("FakePartner")
struct FakePartnerTests {
  /// Waits a moment instead of a real time, so a test does not run for seconds.
  private static let quick = FakePartnerPace(
    arrival: .milliseconds(1), reaction: .milliseconds(10),
    reply: .milliseconds(30),
    petBack: .milliseconds(10), treatBack: .milliseconds(10), sealedFor: .seconds(60),
    adventDoors: [], giftOpened: .milliseconds(10),
    lampFollows: .milliseconds(10),
    idle: [])

  private func collect(
    _ delivery: NoteDelivery, count: Int, after act: @Sendable () async -> Void = {}
  ) async -> [NoteDelivery.Update] {
    var seen: [NoteDelivery.Update] = []
    var updates = delivery.updates().makeAsyncIterator()
    // The connection is open once it has said so; only then does the user act.
    if let first = await updates.next() { seen.append(first) }
    await act()
    while seen.count < count, let update = await updates.next() {
      seen.append(update)
    }
    return seen
  }

  @Test func theFakePartnerArrivesWithALampLit() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let seen = await collect(delivery, count: 3)
    #expect(
      seen.last == .partnerGlow(PartnerGlow(colour: .rose, timeZoneID: FakePartnerRoom.timeZoneID)))
  }

  @Test func theirLampFollowsOursOutAndBackOn() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    var seen = await collect(delivery, count: 4) { await delivery.signal(.lamp(on: false)) }
    #expect(
      seen.last
        == .partnerGlow(
          PartnerGlow(colour: .rose, lampOn: false, timeZoneID: FakePartnerRoom.timeZoneID)))
    seen = await collect(delivery, count: 4) { await delivery.signal(.lamp(on: true)) }
    #expect(
      seen.last
        == .partnerGlow(
          PartnerGlow(colour: .rose, lampOn: true, timeZoneID: FakePartnerRoom.timeZoneID)))
  }

  @Test func aWrappedGiftIsUnwrappedAfterAMoment() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let id = UUID()
    let seen = await collect(delivery, count: 4) {
      await delivery.signal(.gift(id: id, item: "treat-fish"))
    }
    #expect(seen.last == .giftOpened(id))
  }

  @Test func theFakePartnerArrivesAfterConnecting() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let seen = await collect(delivery, count: 2)
    #expect(seen == [.status(.connecting), .status(.partnerHere)])
  }

  @Test func aSentNoteIsReactedToThenAnswered() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let id = UUID()
    let seen = await collect(delivery, count: 5) {
      await delivery.deliver([], id)
    }
    guard seen.count == 5 else {
      Issue.record("saw \(seen)")
      return
    }
    #expect(seen[3] == .reactions([id: .heart]))
    if case .note(let strokes, _) = seen[4] {
      #expect(!strokes.isEmpty)
    } else {
      Issue.record("expected a note, got \(seen[4])")
    }
  }

  @Test func aPetIsPettedBack() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let seen = await collect(delivery, count: 4) {
      await delivery.play(.pet, "2026-11-02T08:00:00+01:00")
    }
    #expect(seen.last == .partnerPetted)
  }

  @Test func aTreatIsAnsweredWithTheFakePartnersOwnToday() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me",
      room: FakePartnerRoom(
        pace: Self.quick, now: { Date(timeIntervalSince1970: 1_800_000_000) }))
    let seen = await collect(delivery, count: 4) {
      await delivery.play(.treat, "x")
    }
    let day = TreatDay.key(for: Date(timeIntervalSince1970: 1_800_000_000), calendar: .current)
    #expect(seen.last == .treats([day: [FakePartnerRoom.device]]))
  }

  @Test func theFakePartnersPetsCountInTheCatsLife() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let seen = await collect(delivery, count: 5) {
      await delivery.life(LifeEvent(kind: .pet, by: "me", at: .now))
    }
    guard case .life(let events) = seen.last else {
      Issue.record("expected a life event, got \(String(describing: seen.last))")
      return
    }
    #expect(events.map(\.kind) == [.pet])
    #expect(events.map(\.by) == [FakePartnerRoom.device])
  }

  @Test func theCatNameIsEchoed() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let seen = await collect(delivery, count: 4) { await delivery.nameCat("Mochi") }
    #expect(seen.last == .catName("Mochi"))
  }

  @Test func theLightSwitchIsEchoedLikeTheRoomDoes() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let seen = await collect(delivery, count: 4) { await delivery.switchLight(.cosy) }
    #expect(seen.contains(.roomLight(.cosy)))
  }

  @Test func theStyleIsEchoedLikeTheRoomDoes() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let style = RoomStyle(wall: .sage, curtains: .linen, drape: .half)
    let seen = await collect(delivery, count: 4) { await delivery.restyle(style) }
    #expect(seen.contains(.roomStyle(style)))
  }

  @Test func anArrangementIsEchoedLikeTheRoomDoes() async {
    let delivery = NoteDelivery.fakePartner(
      device: "me", room: FakePartnerRoom(pace: Self.quick))
    let arranged = RoomArrangement(
      room: "windowSeat.cosyNook", spots: ["knitPouf-3": PieceSpot(x: 3, z: 5, yaw: 0)])
    let seen = await collect(delivery, count: 4) { await delivery.arrange(arranged) }
    #expect(seen.contains(.roomArranged(arranged)))
  }

  @Test func idleMovesCycleThroughNotesPetsAndTreats() async {
    var pace = Self.quick
    pace.idle = [.milliseconds(1)]
    let delivery = NoteDelivery.fakePartner(device: "me", room: FakePartnerRoom(pace: pace))
    let seen = await collect(delivery, count: 13)
    let kinds = seen.dropFirst(3).compactMap { update -> String? in
      switch update {
      case .life(let events): events.map { "life \($0.kind.rawValue)" }.joined()
      case .note: "note"
      case .partnerPetted: "pet"
      case .treats: "treat"
      case .sealedNote: "sealed"
      case .gift: "gift"
      default: "other"
      }
    }
    #expect(
      kinds.prefix(8) == [
        "note", "life note", "pet", "life pet", "treat", "life feed", "sealed", "life play",
      ])
  }

  @Test func everyDrawingHasInkInsideTheUnitSquare() {
    for number in 0..<10 {
      let strokes = FakePartnerDrawings.drawing(number: number)
      #expect(!strokes.isEmpty)
      for point in strokes.flatMap(\.points) {
        #expect((0...1).contains(point.x) && (0...1).contains(point.y))
      }
    }
  }

  @Test func theDrawingsDiffer() {
    let first = (0..<5).map { FakePartnerDrawings.drawing(number: $0) }
    #expect(Set(first).count == 5)
  }
}
