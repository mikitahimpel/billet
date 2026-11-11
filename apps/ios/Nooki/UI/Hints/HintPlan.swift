import Foundation

nonisolated enum HintScreen: Hashable {
    case world, moments, shop, other
}

nonisolated struct HintContext: Hashable {
    var screen: HintScreen
    var onboarded = true
    /// A sheet, a cover, the purchase moment or a game is up: no hint over it.
    var busy = false
    var hasRoomChoice = false
    var canAffordTreat = false
    /// What the person has already done, read from the stores. A hint for a thing done is never shown.
    var petted = false
    var added = false
    var usedMoments = false
    /// The Moments tab has nothing to point at yet: its empty state has the action, and the hint's popover over the
    /// tab bar would cover it on a small phone.
    var momentsEmpty = false
    var purchased = false
    var switchedRooms = false
    var gaveTreat = false
}

/// Which hint, if any, a screen visit shows. Each hint has one trigger; when several are due, the first in `order`
/// wins. A seen hint never comes back, one visit shows at most one hint and one session at most `perSession`.
nonisolated enum HintPlan {
    static let order = [
        PetHint.hintId, NeedsHint.hintId, AddHint.hintId, MomentsHint.hintId, ShopHint.hintId,
        RoomsHint.hintId, TreatHint.hintId,
    ]
    static let perSession = 2
    static let settle: Duration = .seconds(1)

    static func next(_ context: HintContext, seen: Set<String>, shownThisSession: Int) -> String? {
        guard context.onboarded, !context.busy, shownThisSession < perSession else { return nil }
        return order.first { !seen.contains($0) && !used($0, context) && isDue($0, context, seen: seen) }
    }

    /// The hint's feature was used before the hint showed.
    static func used(_ id: String, _ context: HintContext) -> Bool {
        switch id {
        case PetHint.hintId: context.petted
        case AddHint.hintId: context.added
        case MomentsHint.hintId: context.usedMoments
        case ShopHint.hintId: context.purchased
        case RoomsHint.hintId: context.switchedRooms
        case TreatHint.hintId: context.gaveTreat
        default: false
        }
    }

    /// The hints `context` makes pointless: they count as seen without showing.
    static func skipped(_ context: HintContext, seen: Set<String>) -> [String] {
        order.filter { !seen.contains($0) && used($0, context) }
    }

    static func isDue(_ id: String, _ context: HintContext, seen: Set<String>) -> Bool {
        let world = context.screen == .world
        let metCat = seen.contains(PetHint.hintId)
        switch id {
        case PetHint.hintId: return world
        case NeedsHint.hintId: return world && metCat
        case AddHint.hintId: return world && metCat
        case MomentsHint.hintId: return context.screen == .moments && !context.momentsEmpty
        case ShopHint.hintId: return context.screen == .shop
        case RoomsHint.hintId: return world && metCat && context.hasRoomChoice
        case TreatHint.hintId: return world && metCat && context.canAffordTreat
        default: return false
        }
    }
}

/// The `hints` experiment's variant that sees no hints. Its pairs still run the plan and report the hints they would
/// have had, as `<id>-hold`, so the admin can compare what they do with the pairs that saw them.
nonisolated enum HintHoldout {
    static let hold = "hold"

    static func detail(_ id: String) -> String { id + "-hold" }
}
