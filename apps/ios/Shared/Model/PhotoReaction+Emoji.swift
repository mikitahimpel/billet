import Wire

nonisolated extension PhotoReaction {
    /// The same emoji the server puts in a reaction's push.
    var emoji: String {
        switch self {
        case .heart: "❤️"
        case .laugh: "😂"
        case .wow: "😮"
        case .sad: "😢"
        case .fire: "🔥"
        }
    }

    var label: String {
        switch self {
        case .heart: "Love"
        case .laugh: "Laugh"
        case .wow: "Wow"
        case .sad: "Sad"
        case .fire: "Fire"
        }
    }
}
