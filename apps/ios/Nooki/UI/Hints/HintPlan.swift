import Foundation

/// The screen a hint can point at.
nonisolated enum HintScreen: Hashable {
    case world, moments, shop, other
}

/// What the app looks like when a screen visit settles: the facts the hint triggers read.
nonisolated struct HintContext: Hashable {
    var screen: HintScreen
    var onboarded = true
    /// A sheet, a cover, the purchase moment or a game is up: no hint over it.
    var busy = false
    /// The room switch is there to point at.
    var hasRoomChoice = false
    var canAffordTreat = false
}

/// Which hint, if any, a screen visit shows. Each hint has one trigger; when several are due, the first in `order`
/// wins. A seen hint never comes back, one visit shows at most one hint and one session at most `perSession`.
nonisolated enum HintPlan {
    static let order = [
        PetHint.hintId, AddHint.hintId, MomentsHint.hintId, ShopHint.hintId, RoomsHint.hintId,
        TreatHint.hintId,
    ]
    static let perSession = 2
    /// How long a screen stays still before its hint shows.
    static let settle: Duration = .seconds(1)

    static func next(_ context: HintContext, seen: Set<String>, shownThisSession: Int) -> String? {
        guard context.onboarded, !context.busy, shownThisSession < perSession else { return nil }
        return order.first { !seen.contains($0) && isDue($0, context, seen: seen) }
    }

    /// The hint's own trigger.
    static func isDue(_ id: String, _ context: HintContext, seen: Set<String>) -> Bool {
        let world = context.screen == .world
        let metCat = seen.contains(PetHint.hintId)
        switch id {
        case PetHint.hintId: return world
        case AddHint.hintId: return world && metCat
        case MomentsHint.hintId: return context.screen == .moments
        case ShopHint.hintId: return context.screen == .shop
        case RoomsHint.hintId: return world && metCat && context.hasRoomChoice
        case TreatHint.hintId: return world && metCat && context.canAffordTreat
        default: return false
        }
    }
}
