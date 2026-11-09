import Foundation
import MoodInterface
import Observation
import Wire

/// Earns nothing, so nobody taps it for coins.
typealias PartnerMood = CheckInMood

nonisolated extension PartnerMood {
    var title: String {
        switch self {
        case .happy: "happy"
        case .sleepy: "sleepy"
        case .missing: "missing you"
        case .busy: "busy"
        }
    }
}

@Observable
final class MoodStore: MoodChecking {
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

    @discardableResult
    func take(_ check: MoodCheckIn, for partner: String, replacing: Bool = false) -> Bool {
        guard MoodCheckIn.take(check, for: partner, into: &latest, replacing: replacing) else { return false }
        SharedFile.write(latest, to: Self.file)
        return true
    }
}
