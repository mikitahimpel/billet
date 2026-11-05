import Foundation
import Testing
@testable import Billet

@Suite struct HintPlanTests {
    private func next(_ context: HintContext, seen: Set<String> = [], shown: Int = 0) -> String? {
        HintPlan.next(context, seen: seen, shownThisSession: shown)
    }

    @Test func theFirstWorldVisitMeetsTheCat() {
        #expect(next(HintContext(screen: .world)) == "pet")
    }

    @Test func nothingShowsDuringTheOnboardingOrOverSomethingElse() {
        #expect(next(HintContext(screen: .world, onboarded: false)) == nil)
        #expect(next(HintContext(screen: .world, busy: true)) == nil)
        #expect(next(HintContext(screen: .shop, busy: true)) == nil)
    }

    @Test func aPartnerToInviteComesRightAfterTheCat() {
        let unpaired = HintContext(screen: .world, canInvite: true, hasRoomChoice: true, canAffordTreat: true)
        #expect(next(unpaired, seen: ["pet"]) == "invite")
        #expect(next(unpaired, seen: ["pet", "invite"]) == "add")
        var paired = unpaired
        paired.canInvite = false
        #expect(next(paired, seen: ["pet"]) == "add")
    }

    @Test func worldHintsFollowAFixedOrder() {
        let world = HintContext(screen: .world, hasRoomChoice: true, canAffordTreat: true)
        #expect(next(world, seen: ["pet", "add"]) == "rooms")
        #expect(next(world, seen: ["pet", "add", "rooms"]) == "treat")
        #expect(next(world, seen: ["pet", "add", "rooms", "treat"]) == nil)
    }

    @Test func eachTabHintWaitsForItsFirstVisit() {
        #expect(next(HintContext(screen: .moments)) == "moments")
        #expect(next(HintContext(screen: .shop)) == "shop")
        #expect(next(HintContext(screen: .shop), seen: ["shop"]) == nil)
        #expect(next(HintContext(screen: .other)) == nil)
        #expect(next(HintContext(screen: .world), seen: ["pet", "add"]) == nil)
    }

    @Test func aFeatureHintWaitsForItsFeature() {
        let world = HintContext(screen: .world)
        #expect(next(world, seen: ["pet", "add"]) == nil)
        #expect(next(HintContext(screen: .world, hasRoomChoice: true), seen: ["pet", "add"]) == "rooms")
        #expect(next(HintContext(screen: .world, canAffordTreat: true), seen: ["pet", "add"]) == "treat")
        // Without the cat first, a feature hint doesn't jump the queue.
        #expect(next(HintContext(screen: .world, hasRoomChoice: true)) == "pet")
    }

    @Test func aSessionShowsAtMostTwo() {
        #expect(next(HintContext(screen: .shop), shown: 1) == "shop")
        #expect(next(HintContext(screen: .shop), shown: HintPlan.perSession) == nil)
    }

    @Test func everyHintIsInTheOrderOnce() {
        #expect(Set(HintPlan.order) == Set(Hints.all.map { $0.hintId }))
        #expect(HintPlan.order.count == Hints.all.count)
    }
}

@MainActor @Suite struct HintsTests {
    let defaults: UserDefaults

    init() {
        let name = "hints-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    private func hints(presenting: Bool = false) -> Hints {
        let hints = Hints(report: { _ in }, defaults: defaults, isPresenting: { presenting })
        hints.onboardingFinished(true)
        return hints
    }

    @Test func aShownHintNeverComesBack() {
        let first = hints()
        #expect(first.plan(HintContext(screen: .world)) == "pet")
        first.appeared(PetHint())
        #expect(first.plan(HintContext(screen: .world)) == "add")
        // A new launch remembers it.
        #expect(hints().plan(HintContext(screen: .world)) == "add")
    }

    @Test func doneOrClosedCountsAsSeen() {
        let hints = hints()
        hints.done(PetHint())
        hints.close(AddHint())
        #expect(hints.seen == ["pet", "add"])
        #expect(hints.plan(HintContext(screen: .world)) == nil)
    }

    @Test func theSessionCapCountsWhatShowed() {
        let hints = hints()
        hints.appeared(PetHint())
        hints.appeared(PetHint())
        #expect(hints.plan(HintContext(screen: .shop)) == "shop")
        hints.appeared(ShopHint())
        #expect(hints.plan(HintContext(screen: .moments)) == nil)
    }

    @Test func aSheetOverTheAppHoldsHintsBack() {
        #expect(hints(presenting: true).plan(HintContext(screen: .world)) == nil)
    }

    @Test func nothingBeforeTheOnboardingEnds() {
        let hints = Hints(report: { _ in }, defaults: defaults, isPresenting: { false })
        #expect(hints.plan(HintContext(screen: .world)) == nil)
        hints.canInvite(true)
        hints.onboardingFinished(true)
        hints.appeared(PetHint())
        #expect(hints.plan(HintContext(screen: .world)) == "invite")
    }
}
