import GamesInterface
import Pet
import SwiftUI
import Design

/// How a need reads on screen: met, fine for now, or wanting something. A low need is an invitation, never a warning:
/// nothing turns red, blinks or shakes.
nonisolated enum NeedLevel: Hashable, CaseIterable, Sendable {
    case content
    case okay
    case wants

    /// Met from here up; the room's spoken status draws the same line.
    static let contentFrom = 0.7
    /// The brain's own line for a low need, so the screen and her behaviour agree.
    static let wantsBelow = LifeConfig.standard.lowBelow

    init(_ value: Double) {
        switch value {
        case Self.contentFrom...: self = .content
        case Self.wantsBelow..<Self.contentFrom: self = .okay
        default: self = .wants
        }
    }

    /// The one need raised, on the sheet and as the badge on her portrait on Home: the lowest, while it wants something.
    /// Only one, so the eye always lands on what comes first.
    static func cue(_ needs: PetNeeds) -> PetNeed? {
        let (need, value) = needs.lowest
        return NeedLevel(value) == .wants ? need : nil
    }
}

/// What a tap does for a need.
nonisolated enum NeedCare: Hashable, Sendable {
    case game(MiniGame)
    case pet

    /// Also the button's accessibility identifier, which the UI tests tap.
    var title: String {
        switch self {
        case .game(.feed): "Feed"
        case .game(.water): "Water"
        case .game(.laser): "Play"
        case .game(.brush): "Brush"
        case .pet: "Pet"
        }
    }

    var symbol: String {
        switch self {
        case .game(.feed): "fork.knife"
        case .game(.water): "drop.fill"
        case .game(.laser): "tennisball.fill"
        case .game(.brush): "paintbrush.fill"
        case .pet: "hand.raised.fill"
        }
    }

    func hint(name: String) -> String {
        switch self {
        case .game(.feed): "Weigh out \(name)'s dinner"
        case .game(.water): "Fill \(name)'s water bowl"
        case .game(.laser): "Play with the laser dot"
        case .game(.brush): "Brush \(name)'s coat"
        case .pet: "Gives \(name) a pet"
        }
    }

    /// The care that no need's row offers, under the rows.
    static let more: [NeedCare] = [.game(.water), .game(.brush)]

    /// Under the rows; before her needs are known there are no rows, so every care goes there.
    static func extra(needsKnown: Bool) -> [NeedCare] {
        needsKnown ? more : PetNeed.displayOrder.compactMap(\.care) + more
    }
}

nonisolated extension PetNeed {
    static let displayOrder: [PetNeed] = [.full, .rested, .playful, .loved]

    var symbol: String {
        switch self {
        case .full: "fork.knife"
        case .rested: "moon.zzz.fill"
        case .playful: "tennisball.fill"
        case .loved: "heart.fill"
        }
    }

    /// Blush is love and hearts only; the rest are honey, told apart by their glyph.
    var tint: Color {
        switch self {
        case .full, .rested, .playful: .honey
        case .loved: .blushPink
        }
    }

    /// Nil for rest, which only sleep fills.
    var care: NeedCare? {
        switch self {
        case .full: .game(.feed)
        case .rested: nil
        case .playful: .game(.laser)
        case .loved: .pet
        }
    }

    /// Why a need without care has no action.
    var note: String? {
        switch self {
        case .rested: "Naps on her own"
        case .full, .playful, .loved: nil
        }
    }

    func word(_ level: NeedLevel) -> String {
        switch (self, level) {
        case (.full, .content): "Well fed"
        case (.full, .okay): "Peckish"
        case (.full, .wants): "Hungry"
        case (.rested, .content): "Wide awake"
        case (.rested, .okay): "Drowsy"
        case (.rested, .wants): "Sleepy"
        case (.playful, .content): "Had fun"
        case (.playful, .okay): "Curious"
        case (.playful, .wants): "Wants to play"
        case (.loved, .content): "Adored"
        case (.loved, .okay): "Cuddly"
        case (.loved, .wants): "Wants a cuddle"
        }
    }

    /// The word, then the number the screen leaves out.
    func spoken(_ value: Double) -> String {
        "\(word(NeedLevel(value))), \(Int((value * 100).rounded())) percent"
    }

    func line(_ level: NeedLevel, name: String) -> String {
        switch (self, level) {
        case (.full, .content): "Happily full"
        case (.full, .okay): "Could nibble something"
        case (.full, .wants): "\(name) would love a meal"
        case (.rested, .content): "Well rested"
        case (.rested, .okay): "A little sleepy"
        case (.rested, .wants): "\(name) would love a cozy nap"
        case (.playful, .content): "Had a lovely play"
        case (.playful, .okay): "Up for a game"
        case (.playful, .wants): "\(name) would love to play"
        case (.loved, .content): "Feels so loved"
        case (.loved, .okay): "Glad you're here"
        case (.loved, .wants): "\(name) would love a cuddle"
        }
    }
}

nonisolated extension PetNeeds {
    /// Her mood in a few words, from her lowest need.
    func moodLine(name: String) -> String {
        let (need, value) = lowest
        let level = NeedLevel(value)
        return level == .content ? "Happy and cosy" : need.line(level, name: name)
    }
}
