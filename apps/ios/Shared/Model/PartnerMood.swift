import Foundation
import Observation

/// One-tap check-in a partner leaves for the other, mostly from the widget.
/// Earns nothing, so nobody taps it for coins. Nonisolated because App Intents take it as a parameter.
nonisolated enum PartnerMood: String, Codable, CaseIterable, Sendable {
    case happy, sleepy, missing, busy

    var title: String {
        switch self {
        case .happy: "happy"
        case .sleepy: "sleepy"
        case .missing: "missing you"
        case .busy: "busy"
        }
    }
}

nonisolated struct MoodCheckIn: Codable, Hashable {
    var mood: PartnerMood
    var date: Date
    /// A few words with the mood, at most `MoodCheckIn.noteLimit` UTF-16 units, as the server keeps it.
    var note: String? = nil

    static let noteLimit = 80

    /// Trimmed, cut to the limit, and nil when nothing is left.
    static func clean(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        var cut = trimmed
        while cut.utf16.count > noteLimit { cut.removeLast() }
        return cut
    }

    /// From the last day: what the header and the widgets show.
    func isFresh(at now: Date = .now) -> Bool { date > now.addingTimeInterval(-86_400) }
}

@Observable
final class MoodStore {
    /// Latest check-in per partner monogram.
    private(set) var latest: [String: MoodCheckIn] = [:]

    private static let file = "Couple/moods.json"

    init() {
        reload()
    }

    func reload() {
        latest = SharedFile.read([String: MoodCheckIn].self, from: Self.file) ?? [:]
    }

    func set(_ mood: PartnerMood, note: String? = nil, for partner: String, at date: Date = .now) {
        take(MoodCheckIn(mood: mood, date: date, note: MoodCheckIn.clean(note)), for: partner)
    }

    /// Keeps `check` unless a later one is already here, such as one set on this phone before the server heard of it;
    /// `replacing` keeps it anyway, as the server's copy of the one this phone just sent.
    @discardableResult
    func take(_ check: MoodCheckIn, for partner: String, replacing: Bool = false) -> Bool {
        if !replacing, let current = latest[partner], current.date > check.date { return false }
        latest[partner] = check
        SharedFile.write(latest, to: Self.file)
        return true
    }
}
