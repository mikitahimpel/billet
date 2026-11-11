import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UsInterface
import Wire
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

    @Test func herNeedsComeRightAfterTheCatAndThenTheAddButton() {
        let world = HintContext(screen: .world, hasRoomChoice: true, canAffordTreat: true)
        #expect(next(world, seen: ["pet"]) == "needs")
        #expect(next(world, seen: ["pet", "needs"]) == "add")
        // The pair is made in the onboarding: no hint asks for a partner, whatever an older build saw.
        #expect(!HintPlan.order.contains("invite"))
        #expect(next(world, seen: ["pet", "needs", "invite"]) == "add")
    }

    @Test func aPhoneThatSawEveryOlderHintStillLearnsWhereHerNeedsAre() {
        let world = HintContext(screen: .world, hasRoomChoice: true, canAffordTreat: true)
        #expect(next(world, seen: ["pet", "add", "moments", "shop", "rooms", "treat"]) == "needs")
        // Not before she has been met.
        #expect(next(world, seen: ["add"]) == "pet")
    }

    @Test func worldHintsFollowAFixedOrder() {
        let world = HintContext(screen: .world, hasRoomChoice: true, canAffordTreat: true)
        #expect(next(world, seen: ["pet", "needs", "add"]) == "rooms")
        #expect(next(world, seen: ["pet", "needs", "add", "rooms"]) == "treat")
        #expect(next(world, seen: ["pet", "needs", "add", "rooms", "treat"]) == nil)
    }

    @Test func eachTabHintWaitsForItsFirstVisit() {
        #expect(next(HintContext(screen: .moments)) == "moments")
        #expect(next(HintContext(screen: .shop)) == "shop")
        #expect(next(HintContext(screen: .shop), seen: ["shop"]) == nil)
        #expect(next(HintContext(screen: .other)) == nil)
        #expect(next(HintContext(screen: .world), seen: ["pet", "needs", "add"]) == nil)
    }

    @Test func theMomentsHintWaitsForSomethingOnTheTab() {
        #expect(next(HintContext(screen: .moments, momentsEmpty: true)) == nil)
    }

    @Test func aFeatureHintWaitsForItsFeature() {
        let world = HintContext(screen: .world)
        #expect(next(world, seen: ["pet", "needs", "add"]) == nil)
        #expect(next(HintContext(screen: .world, hasRoomChoice: true), seen: ["pet", "needs", "add"]) == "rooms")
        #expect(next(HintContext(screen: .world, canAffordTreat: true), seen: ["pet", "needs", "add"]) == "treat")
        // Without the cat first, a feature hint doesn't jump the queue.
        #expect(next(HintContext(screen: .world, hasRoomChoice: true)) == "pet")
    }

    @Test func aSessionShowsAtMostTwo() {
        #expect(next(HintContext(screen: .shop), shown: 1) == "shop")
        #expect(next(HintContext(screen: .shop), shown: HintPlan.perSession) == nil)
    }

    @Test func aHintForAThingAlreadyDoneIsNeverDue() {
        let used: [(String, HintContext)] = [
            ("pet", HintContext(screen: .world, petted: true)),
            ("add", HintContext(screen: .world, added: true)),
            ("moments", HintContext(screen: .moments, usedMoments: true)),
            ("shop", HintContext(screen: .shop, purchased: true)),
            ("rooms", HintContext(screen: .world, hasRoomChoice: true, switchedRooms: true)),
            ("treat", HintContext(screen: .world, canAffordTreat: true, gaveTreat: true)),
        ]
        for (id, context) in used {
            #expect(HintPlan.skipped(context, seen: []) == [id])
            #expect(next(context) != id)
        }
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
        #expect(first.plan(HintContext(screen: .world)) == "needs")
        // A new launch remembers it.
        #expect(hints().plan(HintContext(screen: .world)) == "needs")
    }

    @Test func doneOrClosedCountsAsSeen() {
        let hints = hints()
        hints.done(PetHint())
        hints.done(NeedsHint())
        hints.close(AddHint())
        #expect(hints.seen == ["pet", "needs", "add"])
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

    @Test func everyHintShowsOnceAndNeverAgain() {
        func due(_ id: String) -> HintContext {
            switch id {
            case MomentsHint.hintId: HintContext(screen: .moments)
            case ShopHint.hintId: HintContext(screen: .shop)
            default: HintContext(screen: .world, hasRoomChoice: true, canAffordTreat: true)
            }
        }
        for id in HintPlan.order {
            let launch = hints()
            #expect(launch.show(due(id)) == id)
            #expect(launch.seen.contains(id))
            #expect(HintStage.current == id)
            #expect(launch.plan(due(id)) != id)
            #expect(hints().plan(due(id)) != id)
        }
        #expect(hints().show(HintContext(screen: .world, hasRoomChoice: true, canAffordTreat: true)) == nil)
        HintStage.current = ""
    }

    @Test func aSheetOverTheAppHoldsHintsBack() {
        #expect(hints(presenting: true).plan(HintContext(screen: .world)) == nil)
    }

    @Test func nothingBeforeTheOnboardingEnds() {
        let hints = Hints(report: { _ in }, defaults: defaults, isPresenting: { false })
        #expect(hints.plan(HintContext(screen: .world)) == nil)
        hints.onboardingFinished(true)
        hints.appeared(PetHint())
        #expect(hints.plan(HintContext(screen: .world)) == "needs")
    }

    @Test func aHintDoneBeforeItShowsIsSeenAndNeverShown() {
        let hints = hints()
        let petted = HintContext(screen: .world, petted: true)
        #expect(hints.show(petted) == "needs")
        #expect(hints.seen.contains("pet"))
        #expect(self.hints().plan(HintContext(screen: .world, added: true)) == nil)
        HintStage.current = ""
    }

    @Test func aHintShownOnceNeverComesAgainInTheSessionOrAfter() {
        let first = hints()
        #expect(first.show(HintContext(screen: .shop)) == "shop")
        #expect(first.show(HintContext(screen: .shop)) == nil)
        #expect(hints().show(HintContext(screen: .shop)) == nil)
        HintStage.current = ""
    }

    @Test func aSessionShowsAtMostTwoHints() {
        let hints = hints()
        #expect(hints.show(HintContext(screen: .shop)) == "shop")
        #expect(hints.show(HintContext(screen: .moments)) == "moments")
        #expect(hints.show(HintContext(screen: .world)) == nil)
        HintStage.current = ""
    }

    @Test func theHoldoutRunsThePlanButDrawsNothingAndReportsItsOwnIds() async throws {
        let events = Recorded()
        let hints = Hints(report: { await events.add($0) }, defaults: defaults, isPresenting: { false })
        hints.onboardingFinished(true)
        hints.isHeldOut = { true }
        #expect(hints.show(HintContext(screen: .shop)) == "shop")
        #expect(HintStage.current == "")
        hints.done(ShopHint())
        try await Task.sleep(for: .milliseconds(200))
        let sent = await events.all
        #expect(sent.map(\.detail) == ["shop-hold", "shop-hold"])
        #expect(sent.map(\.name) == [.tipShown, .tipAction])
    }

    @Test func anActionCountsOnlyWithin24HoursOfTheShow() async throws {
        let clock = TestClock()
        let events = Recorded()
        let hints = Hints(
            report: { await events.add($0) }, defaults: defaults, isPresenting: { false }, now: { clock.date })
        hints.onboardingFinished(true)
        hints.appeared(ShopHint())
        clock.date.addTimeInterval(Hints.actionWindow + 1)
        hints.done(ShopHint())
        try await Task.sleep(for: .milliseconds(200))
        #expect(await events.all.map(\.name) == [.tipShown])
    }
}

private actor Recorded {
    private(set) var all: [ClientEvent] = []
    func add(_ events: [ClientEvent]) { all += events }
}

private final class TestClock: @unchecked Sendable {
    nonisolated(unsafe) var date = Date(timeIntervalSince1970: 1_800_000_000)
}
