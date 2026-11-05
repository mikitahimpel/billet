import Foundation
import Transport
import Wire

/// The couple's check-ins in step with the pair's room: one sent for each set here, and each one the room has taken
/// into the phone's `MoodStore`, which the header and the widgets read.
@MainActor
struct MoodSync {
    var send: @Sendable (SetMoodRequest) async throws(TransportError) -> PartnerCheckIn
    let moods: MoodStore
    let couple: CoupleStore

    /// The room's check-ins when the phone follows the pair. One the viewer set here later, such as from a widget
    /// while the app was away, goes up now.
    func follow(_ checkIns: [PartnerCheckIn]) async {
        checkIns.forEach { received($0) }
        let viewer = couple.couple.viewer
        guard let mine = moods.latest[viewer] else { return }
        let sent = checkIns.first { monogram(of: $0.user) == viewer }.map(Self.date(of:))
        if sent.map({ mine.date > $0.addingTimeInterval(1) }) ?? true { await share(mine) }
    }

    /// Sends a check-in set on this phone. The room's answer, at the room's time, takes its place, so a phone whose
    /// clock runs ahead doesn't send it again on the next follow.
    func share(_ check: MoodCheckIn) async {
        guard let mood = CheckInMood(rawValue: check.mood.rawValue) else { return }
        if let stored = try? await send(SetMoodRequest(mood: mood, note: check.note)) {
            received(stored, replacing: true)
        }
    }

    /// A check-in from the room, the partner's or this account's own from another phone.
    func received(_ checkIn: PartnerCheckIn, replacing: Bool = false) {
        guard let partner = monogram(of: checkIn.user), let mood = PartnerMood(rawValue: checkIn.mood.rawValue) else {
            return
        }
        moods.take(
            MoodCheckIn(mood: mood, date: Self.date(of: checkIn), note: checkIn.note), for: partner,
            replacing: replacing)
    }

    private func monogram(of user: UserId) -> String? {
        couple.couple.pair?.users.first { $0.value == user.rawValue }?.key
    }

    nonisolated static func date(of checkIn: PartnerCheckIn) -> Date {
        Date(timeIntervalSince1970: Double(checkIn.at) / 1000)
    }
}
