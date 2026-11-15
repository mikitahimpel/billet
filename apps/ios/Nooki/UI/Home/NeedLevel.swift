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

    /// Which of the sheet's limits it falls under.
    var kind: Care {
        switch self {
        case .game(.feed): .feed
        case .game(.water): .water
        case .game(.laser): .play
        case .game(.brush): .brush
        case .pet: .pet
        }
    }

    /// Why she turns the care down, short enough for a tile's foot; nil while it is welcome.
    func declined(_ verdict: CareGate.Verdict, now: Date) -> String? {
        switch verdict {
        case .open: return nil
        case .refused(.met, _):
            switch self {
            case .game(.feed): return "Full for now"
            case .game(.laser): return "Played out"
            case .pet, .game(.brush): return "Plenty of cuddles"
            case .game(.water): return "Plenty of water"
            }
        case .refused(.tired, let until):
            let minutes = until.map { max(1, Int((($0.timeIntervalSince(now)) / 60).rounded(.up))) }
            return minutes.map { $0 == 1 ? "Rest a minute" : "Rest \($0) min" } ?? "A little rest"
        }
    }

    /// The same, as a sentence for under the sheet, where the care was asked for.
    func declinedSentence(_ verdict: CareGate.Verdict, now: Date, name: String) -> String? {
        guard let foot = declined(verdict, now: now) else { return nil }
        switch verdict {
        case .open: return nil
        case .refused(.met, _):
            switch self {
            case .game(.feed): return "\(name) isn't hungry"
            case .game(.laser): return "\(name) has played enough for now"
            case .pet, .game(.brush): return "\(name) has had plenty of cuddles"
            case .game(.water): return "\(name)'s bowl is fine"
            }
        case .refused(.tired, _): return "\(name) needs a breather. \(foot)"
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
    func note(pronouns: CatPronouns) -> String? {
        switch self {
        case .rested: pronouns.say(.napsOnOwn)
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
    /// When it was, as the strip says it: the minute of something the couple did, the start of the hour of
    /// something she did on her own, and for a night's sleep the hour she woke.
    func time(in zone: TimeZone = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: zone).hour().minute()
        switch kind {
        case .slept: return "till " + Date(timeIntervalSince1970: until).formatted(style)
        case .napped, .ate, .played, .watched, .explored, .groomed, .mischief, .soughtYou, .playedTogether, .petted,
            .gotNote:
            return Date(timeIntervalSince1970: at).formatted(style)
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
