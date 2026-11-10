import Foundation
import MoodInterface
import Persistence
import Wire

/// Earns nothing, so nobody taps it for coins.
public typealias PartnerMood = CheckInMood

nonisolated extension PartnerMood {
    public var title: String {
        switch self {
        case .happy: "happy"
        case .sleepy: "sleepy"
        case .missing: "missing you"
        case .busy: "busy"
        }
    }
}

extension MoodStore {
    private static let file = "Couple/moods.json"

    /// The App Group file the app, the widgets and the intents share.
    public convenience init() {
        self.init(
            load: { SharedFile.read([String: MoodCheckIn].self, from: Self.file) },
            save: { SharedFile.write($0, to: Self.file) }
        )
    }
}
