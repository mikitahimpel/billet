import FeatureInbox
import Foundation
import Persistence
import Pet
import Testing
import WidgetBridge
import Wire

@testable import FeatureHome

@Suite struct WidgetPublisherTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func at(_ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
  }

  private func note(_ direction: NoteRecord.Direction, _ date: Date) -> NoteRecord {
    NoteRecord(direction: direction, date: date, strokes: [])
  }

  @Test func snapshotCarriesTheDaysPlayAndTheNotes() {
    var play = PairPlay(device: "me")
    _ = play.treatGiven(on: "2026-11-10")
    play.named("Mochi")
    let received = note(.received, at(9))
    let notes = [received, note(.sent, at(8)), note(.sent, at(3))]
    let snapshot = WidgetPublisher.snapshot(
      play: play, notes: notes, partnerHere: true, previous: nil, now: at(10), calendar: calendar)
    #expect(snapshot.catName == "Mochi")
    #expect(snapshot.treat == .waitingOnPartner)
    #expect(snapshot.treatDay == "2026-11-10")
    #expect(snapshot.partnerHere)
    #expect(snapshot.lastSentAt == at(8))
    #expect(snapshot.lastReceivedAt == at(9))
    #expect(snapshot.latestReceivedNote == received.id)
    #expect(snapshot.pairedSince == at(3))
  }

  @Test func pairedSinceKeepsTheEarliestKnownDay() {
    let play = PairPlay(device: "me")
    let first = WidgetPublisher.snapshot(
      play: play, notes: [], partnerHere: false, previous: nil, now: at(2), calendar: calendar)
    #expect(first.pairedSince == at(2))
    let later = WidgetPublisher.snapshot(
      play: play, notes: [note(.sent, at(5))], partnerHere: false, previous: first, now: at(9),
      calendar: calendar)
    #expect(later.pairedSince == at(2))
  }

  @Test func publishingWritesOnceAndReloadsOnlyOnChange() throws {
    let storage = AppGroupStorageFake.make()
    let reloads = Counter()
    let publisher = WidgetPublisher(
      store: WidgetSnapshotStore(storage: storage), reload: { reloads.bump() })
    let play = PairPlay(device: "me")
    publisher.publish(play: play, notes: [], partnerHere: false, now: at(10), calendar: calendar)
    publisher.publish(
      play: play, notes: [], partnerHere: false, now: at(10, 13), calendar: calendar)
    #expect(reloads.value == 1)
    publisher.publish(play: play, notes: [], partnerHere: true, now: at(10, 14), calendar: calendar)
    #expect(reloads.value == 2)
    publisher.clear()
    #expect(WidgetSnapshotStore(storage: storage).load() == nil)
    #expect(reloads.value == 3)
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func bump() { lock.withLock { count += 1 } }
}

private enum AppGroupStorageFake {
  static func make() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }
}
