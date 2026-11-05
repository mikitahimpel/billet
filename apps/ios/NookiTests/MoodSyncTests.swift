import Foundation
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

/// The room's side of the check-ins: what it was sent, and what it answers.
private nonisolated final class FakeMoodRoom: Sendable {
    let sent = Mutex<[SetMoodRequest]>([])
    /// The room's clock, in milliseconds.
    let now = Mutex(0)

    func send(as user: String) -> @Sendable (SetMoodRequest) async throws(TransportError) -> PartnerCheckIn {
        { (request) async throws(TransportError) in
            self.sent.withLock { $0.append(request) }
            return PartnerCheckIn(user: UserId(user), mood: request.mood, note: request.note, at: self.now.withLock { $0 })
        }
    }
}

private nonisolated func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

@MainActor
@Suite(.serialized) struct MoodSyncTests {
    private let moods = MoodStore()
    private let couple = CoupleStore()

    private func paired() -> (me: String, partner: String) {
        couple.adopt(pairID: "pair-1", me: "user-me", partner: "user-them")
        return (couple.couple.viewer, couple.couple.other)
    }

    private func cleanUp() {
        couple.leavePair()
        SharedFile.flush()
        try? FileManager.default.removeItem(at: SharedFile.url("Couple/moods.json"))
        moods.reload()
    }

    @Test func thePartnersCheckInShowsUnderTheirMonogram() {
        defer { cleanUp() }
        let (_, partner) = paired()
        let sync = MoodSync(send: FakeMoodRoom().send(as: "user-me"), moods: moods, couple: couple)
        let at = Date.now.addingTimeInterval(-60)

        sync.received(PartnerCheckIn(user: UserId("user-them"), mood: .missing, note: "call me?", at: ms(at)))
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
        defer { cleanUp() }
        let (me, _) = paired()
        let room = FakeMoodRoom()
        let roomTime = Date.now.addingTimeInterval(-5)
        room.now.withLock { $0 = ms(roomTime) }
        let sync = MoodSync(send: room.send(as: "user-me"), moods: moods, couple: couple)

        moods.set(.sleepy, note: "  long day  ", for: me)
        await sync.share(moods.latest[me]!)

        #expect(room.sent.withLock { $0 } == [SetMoodRequest(mood: .sleepy, note: "long day")])
        #expect(moods.latest[me]?.date == MoodSync.date(of: PartnerCheckIn(
            user: UserId("user-me"), mood: .sleepy, at: ms(roomTime))))
    }

    @Test func followingThePairSendsOnlyACheckInTheRoomHasNotSeen() async {
        defer { cleanUp() }
        let (me, partner) = paired()
        let room = FakeMoodRoom()
        let sync = MoodSync(send: room.send(as: "user-me"), moods: moods, couple: couple)
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

    @Test func aNoteIsTrimmedAndCutToWhatTheServerKeeps() {
        #expect(MoodCheckIn.clean("   ") == nil)
        #expect(MoodCheckIn.clean(nil) == nil)
        #expect(MoodCheckIn.clean(" hi ") == "hi")
        let long = String(repeating: "😴", count: 50)
        #expect(MoodCheckIn.clean(long)?.utf16.count == MoodCheckIn.noteLimit)
    }
}
