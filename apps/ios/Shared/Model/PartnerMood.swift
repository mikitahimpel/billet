import Foundation
import Observation

/// One-tap check-in a partner leaves for the other, mostly from the widget (docs/widget-concept.md, section 2).
/// Earns nothing, so nobody taps it for coins. Nonisolated because App Intents take it as a parameter.
nonisolated enum PartnerMood: String, Codable, CaseIterable, Sendable {
    case happy, sleepy, missing, busy

    var emoji: String {
        switch self {
        case .happy: "😊"
        case .sleepy: "😴"
        case .missing: "🥺"
        case .busy: "📚"
        }
    }

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

    func set(_ mood: PartnerMood, for partner: String, at date: Date = .now) {
        latest[partner] = MoodCheckIn(mood: mood, date: date)
        SharedFile.write(latest, to: Self.file)
    }
}
