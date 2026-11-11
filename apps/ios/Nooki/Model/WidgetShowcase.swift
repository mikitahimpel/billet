import Foundation

/// What the widget gallery in Settings lists: each widget Ourio ships, with the picture of it the gallery test rendered
/// (`WidgetPreviews` in the asset catalog) and the words that say what it is for.
struct WidgetShowcase: Identifiable, Equatable {
    enum Group: CaseIterable {
        case homeScreen, lockScreen, controls

        var title: String {
            switch self {
            case .homeScreen: "Home Screen"
            case .lockScreen: "Lock Screen"
            case .controls: "Controls"
            }
        }

        var footer: String? {
            switch self {
            case .homeScreen: "Small, medium and large sizes. Touch and hold the Home Screen, tap +, then pick Ourio."
            case .lockScreen: "Touch and hold the Lock Screen, tap Customize, then pick Lock Screen and add one."
            case .controls: "Add them to Control Center, or to the Lock Screen in place of the flashlight and camera."
            }
        }
    }

    let id: String
    let group: Group
    let title: String
    let detail: String
    /// Name of the preview in the asset catalog; nil for a control, which has none.
    let preview: String?
    let symbol: String

    static let all: [WidgetShowcase] = [
        .init(id: "cat", group: .homeScreen, title: "Mochi",
              detail: "How she is right now, asleep, waiting or purring, with a pet button and a hug for your partner.",
              preview: "WidgetMochi", symbol: "pawprint.fill"),
        .init(id: "us", group: .homeScreen, title: "Days together",
              detail: "Your days together, the next date and the streak.",
              preview: "WidgetUs", symbol: "heart.fill"),
        .init(id: "partner", group: .homeScreen, title: "From your partner",
              detail: "Their latest drawing or mood on a stamped card. Tap to reply.",
              preview: "WidgetPartner", symbol: "envelope.fill"),
        .init(id: "coins", group: .homeScreen, title: "Coins",
              detail: "Your coins and how far Mochi's care has come.",
              preview: "WidgetCoins", symbol: "star.circle.fill"),
        .init(id: "memory", group: .homeScreen, title: "Memory",
              detail: "A pinned moment, printed like a photo.",
              preview: "WidgetMemory", symbol: "photo.fill"),
        .init(id: "day", group: .homeScreen, title: "Our day",
              detail: "Mochi, your days together and your partner in one large widget.",
              preview: "WidgetDay", symbol: "square.grid.2x2.fill"),
        .init(id: "lock-us", group: .lockScreen, title: "Days together",
              detail: "A number above the clock, or a line with the next date.",
              preview: "WidgetLockUs", symbol: "heart.fill"),
        .init(id: "lock-streak", group: .lockScreen, title: "Streak",
              detail: "A ring that fills toward the next milestone.",
              preview: "WidgetLockStreak", symbol: "flame.fill"),
        .init(id: "lock-cat", group: .lockScreen, title: "Mochi",
              detail: "A glyph for her mood.",
              preview: "WidgetLockCat", symbol: "pawprint.fill"),
        .init(id: "lock-partner", group: .lockScreen, title: "Your partner",
              detail: "How they are, and when they drew you something. Hidden while the phone is locked.",
              preview: "WidgetLockPartner", symbol: "person.fill"),
        .init(id: "control-pet", group: .controls, title: "Pet Your Cat",
              detail: "Mochi purrs, no need to open Ourio.", preview: nil, symbol: "pawprint.fill"),
        .init(id: "control-hug", group: .controls, title: "Send a Hug",
              detail: "Lets your partner know you are thinking of them.", preview: nil, symbol: "heart.fill"),
    ]

    static func items(in group: Group) -> [WidgetShowcase] { all.filter { $0.group == group } }
}
