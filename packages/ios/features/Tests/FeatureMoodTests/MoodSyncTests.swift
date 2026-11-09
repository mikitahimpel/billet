import Foundation
import MoodInterface
import Synchronization
import Testing
import Transport
import Wire

@testable import FeatureMood

/// The room's side of the check-ins: what it was sent, and what it answers.
private final class FakeMoodRoom: Sendable {
  let sent = Mutex<[SetMoodRequest]>([])
  /// The room's clock, in milliseconds.
  let now = Mutex(0)

  func send(as user: String) -> MoodSync.Send {
    { (request) async throws(TransportError) in
      self.sent.withLock { $0.append(request) }
      return PartnerCheckIn(
        user: UserId(user), mood: request.mood, note: request.note, at: self.now.withLock { $0 })
    }
  }
}

private final class FakeMoods: MoodChecking {
  var latest: [String: MoodCheckIn] = [:]

  @discardableResult
  func take(_ check: MoodCheckIn, for partner: String, replacing: Bool = false) -> Bool {
    MoodCheckIn.take(check, for: partner, into: &latest, replacing: replacing)
  }

  func set(_ mood: CheckInMood, note: String? = nil, for partner: String, at date: Date = .now) {
    take(MoodCheckIn(mood: mood, date: date, note: MoodCheckIn.clean(note)), for: partner)
  }
}

private func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

@MainActor
struct MoodSyncTests {
  private let moods = FakeMoods()
  private let me = "M"
  private let partner = "T"

  private func sync(_ room: FakeMoodRoom = FakeMoodRoom()) -> MoodSync {
    let pair = [UserId("user-me"): me, UserId("user-them"): partner]
    return MoodSync(
      send: room.send(as: "user-me"), moods: moods, viewer: { [me] in me },
      monogram: { pair[$0] })
  }

  @Test func thePartnersCheckInShowsUnderTheirMonogram() {
    let sync = sync()
    let at = Date.now.addingTimeInterval(-60)

    sync.received(
      PartnerCheckIn(user: UserId("user-them"), mood: .missing, note: "call me?", at: ms(at)))
    #expect(moods.latest[partner]?.mood == .missing)
    #expect(moods.latest[partner]?.note == "call me?")

    // An older frame, such as a resume replaying the latest, never takes a newer one's place.
    sync.received(PartnerCheckIn(user: UserId("user-them"), mood: .happy, at: ms(at) - 10_000))
    #expect(moods.latest[partner]?.mood == .missing)

    // Someone outside the pair is never shown.
    sync.received(PartnerCheckIn(user: UserId("user-else"), mood: .busy, at: ms(.now)))
    #expect(moods.latest.count == 1)
  }

  @Test func aCheckInSetHereGoesToTheRoomAndTakesItsTime() async {
    let room = FakeMoodRoom()
    let roomTime = Date.now.addingTimeInterval(-5)
    room.now.withLock { $0 = ms(roomTime) }
    let sync = sync(room)

    moods.set(.sleepy, note: "  long day  ", for: me)
    await sync.share(moods.latest[me]!)

    #expect(room.sent.withLock { $0 } == [SetMoodRequest(mood: .sleepy, note: "long day")])
    #expect(
      moods.latest[me]?.date
        == MoodSync.date(
          of: PartnerCheckIn(user: UserId("user-me"), mood: .sleepy, at: ms(roomTime))))
  }

  @Test func followingThePairSendsOnlyACheckInTheRoomHasNotSeen() async {
    let room = FakeMoodRoom()
    let sync = sync(room)
    let earlier = Date.now.addingTimeInterval(-3_600)

    // The room has both; nothing newer here.
    moods.take(MoodCheckIn(mood: .happy, date: earlier), for: me)
    await sync.follow([
      PartnerCheckIn(user: UserId("user-me"), mood: .happy, at: ms(earlier)),
      PartnerCheckIn(user: UserId("user-them"), mood: .busy, at: ms(earlier)),
    ])
    #expect(room.sent.withLock { $0 }.isEmpty)
    #expect(moods.latest[partner]?.mood == .busy)

    // Set from a widget while the app was away: it goes up on the next follow.
    moods.set(.missing, for: me)
    await sync.follow([PartnerCheckIn(user: UserId("user-me"), mood: .happy, at: ms(earlier))])
    #expect(room.sent.withLock { $0 }.map(\.mood) == [.missing])
  }
}
