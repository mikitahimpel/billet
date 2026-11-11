import GamesInterface
import Pet
import SwiftUI
import Design

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
    /// Clockwise from the upper leading quarter of the ring round her portrait, so each need sits where its tile
    /// does in the sheet's two columns.
    static let ringOrder: [PetNeed] = [.full, .rested, .loved, .playful]

    var symbol: String {
        switch self {
        case .full: "fork.knife"
        case .rested: "moon.zzz.fill"
        case .playful: "tennisball.fill"
        case .loved: "heart.fill"
        }
    }

    /// One clay tint each, the same on her portrait's ring and on her sheet. Blush is love and hearts only.
    var tint: Color {
        switch self {
        case .full: .honey
        case .rested: .lilac
        case .playful: .sage
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
}

nonisolated extension CatDayMoment.Kind {
    var title: String {
        switch self {
        case .slept: "Slept"
        case .napped: "Napped"
        case .ate: "Ate"
        case .played: "Played"
        case .watched: "Watched"
        case .explored: "Explored"
        case .groomed: "Groomed"
        case .mischief: "Mischief"
        case .soughtYou: "Missed you"
        case .playedTogether: "Played"
        case .petted: "Cuddles"
        case .gotNote: "Got a note"
        }
    }

    var symbol: String {
        switch self {
        case .slept, .napped: "moon.zzz.fill"
        case .ate: "fork.knife"
        case .played: "tennisball.fill"
        case .watched: "binoculars.fill"
        case .explored: "pawprint.fill"
        case .groomed: "sparkles"
        case .mischief: "cup.and.saucer.fill"
        case .soughtYou: "eyes"
        case .playedTogether: "gamecontroller.fill"
        case .petted: "heart.fill"
        case .gotNote: "envelope.fill"
        }
    }

    /// The tint of the need it fed, so the day reads against the gauges above it.
    var tint: Color {
        switch self {
        case .slept, .napped: PetNeed.rested.tint
        case .ate: PetNeed.full.tint
        case .played, .playedTogether, .watched, .explored, .mischief: PetNeed.playful.tint
        case .groomed: PetNeed.rested.tint
        case .soughtYou, .petted, .gotNote: PetNeed.loved.tint
        }
    }
}

nonisolated extension CatDayMoment {
    /// When it was, as the strip says it: the minute of something the couple did, the hour of something she did
    /// on her own, and for a night's sleep the hour she woke.
    func time(in zone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(timeZone: zone)
        style = exact ? style.hour().minute() : style.hour()
        switch kind {
        case .slept: return "till " + Date(timeIntervalSince1970: until).formatted(style)
        case .napped, .ate, .played, .watched, .explored, .groomed, .mischief, .soughtYou, .playedTogether, .petted,
            .gotNote:
            return Date(timeIntervalSince1970: at).formatted(style)
        }
    }
}

nonisolated extension CatPersonality.Trait {
    var tint: Color {
        switch self {
        case .curious, .playful: .sage
        case .lazy: .lilac
        case .cuddly: .blushPink
        case .bold, .vocal: .honey
        }
    }
}

nonisolated extension CatTemperament {
    var symbol: String {
        switch self {
        case .cuddler: "heart.fill"
        case .explorer: "binoculars.fill"
        case .diva: "crown.fill"
        case .sleepyhead: "moon.zzz.fill"
        case .clown: "tennisball.fill"
        }
    }
}
