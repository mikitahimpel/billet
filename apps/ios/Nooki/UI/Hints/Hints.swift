import MomentsInterface
import Observation
import WidgetInterface
import WidgetUI
import SwiftUI
import TipKit
import Transport
import UsInterface
import Wire

@MainActor
@Observable
final class Hints {
    /// "Show hints again" in Settings: the hints start over on the next launch.
    static let resetKey = "hintsReset"
    /// Labs: every hint shows at once, whatever its rules, from the next launch.
    static let showAllKey = "hintsShowAll"
    /// The hints shown, closed or done: none of them comes back.
    static let seenKey = "hintsSeen"
    /// When each hint was shown and not yet acted on: an action counts within `actionWindow` of it.
    static let shownAtKey = "hintsShownAt"
    static let actionWindow: TimeInterval = 24 * 3600

    static let all: [any HintTip.Type] = [
        PetHint.self, NeedsHint.self, AddHint.self, MomentsHint.self, ShopHint.self, RoomsHint.self, TreatHint.self,
    ]

    @ObservationIgnored private let report: @Sendable ([ClientEvent]) async throws(TransportError) -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: [ClientEvent] = []
    @ObservationIgnored private var sending = false
    @ObservationIgnored private(set) var seen: Set<String>
    /// Hints shown since launch, toward `HintPlan.perSession`.
    @ObservationIgnored private var shownThisSession: Set<String> = []
    @ObservationIgnored private var visiting: Task<Void, Never>?
    @ObservationIgnored private var lastVisit: (@MainActor () -> HintContext)?
    @ObservationIgnored private var onboarded = false
    @ObservationIgnored private let isPresenting: @MainActor () -> Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    /// The pair is in the holdout: the plan runs and reports, but nothing is drawn.
    @ObservationIgnored var isHeldOut: @MainActor () -> Bool = { false }

    init(
        report: @escaping @Sendable ([ClientEvent]) async throws(TransportError) -> Void,
        defaults: UserDefaults = .standard,
        isPresenting: @escaping @MainActor () -> Bool = Hints.keyWindowIsPresenting,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.now = now
        self.report = report
        self.defaults = defaults
        self.isPresenting = isPresenting
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
    }

    /// Starts TipKit, once, before any view asks for a hint. Display frequency is TipKit's immediate: `HintPlan`
    /// does the pacing.
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: seenKey)
            defaults.removeObject(forKey: shownAtKey)
            defaults.removeObject(forKey: resetKey)
        }
        if defaults.bool(forKey: showAllKey) { Tips.showAllTipsForTesting() }
        // A `-perf.script` run (Release builds too) measures and photographs the room, not the hints over it.
        if defaults.string(forKey: "perf.script") != nil { Tips.hideAllTipsForTesting() }
        #if DEBUG
        // For screenshots: `-hint treat` shows only that hint, whatever its rules.
        if let only = defaults.string(forKey: "hint"), let hint = all.first(where: { $0.hintId == only }) {
            Tips.showTipsForTesting([hint])
            Tips.hideTipsForTesting(all.filter { $0.hintId != only })
        }
        // The UI tests tap through the app; a popover would take their first tap.
        if defaults.bool(forKey: "uitestNoHints") { Tips.hideAllTipsForTesting() }
        #endif
        HintStage.current = ""
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    /// The end of the onboarding is the first visit to the screen under it.
    func onboardingFinished(_ finished: Bool) {
        let ended = finished && !onboarded
        onboarded = finished
        if ended, let lastVisit { visit(lastVisit) }
    }

    /// A screen came up: the hint on screen goes, and after `HintPlan.settle` the plan may show one for this
    /// visit. `context` is read then, so a sheet opened meanwhile counts.
    func visit(_ context: @escaping @MainActor () -> HintContext) {
        lastVisit = context
        visiting?.cancel()
        HintStage.current = ""
        visiting = Task { [weak self] in
            try? await Task.sleep(for: HintPlan.settle)
            guard !Task.isCancelled, let self else { return }
            show(context())
        }
    }

    /// Puts up the hint the plan picks for `context`, if any. It counts as seen from that moment, whether or not its
    /// popover ever reports appearing, so neither a tab switch nor a relaunch brings it back.
    @discardableResult
    func show(_ context: HintContext) -> String? {
        for id in HintPlan.skipped(context, seen: seen) { see(id) }
        let id = plan(context)
        if let id { shown(id) }
        HintStage.current = id.flatMap { isHeldOut() ? nil : $0 } ?? ""
        return id
    }

    func plan(_ context: HintContext) -> String? {
        var context = context
        context.onboarded = context.onboarded && onboarded
        context.busy = context.busy || isPresenting()
        return HintPlan.next(context, seen: seen, shownThisSession: shownThisSession.count)
    }

    /// The person did the thing the hint points at, whether or not it was on screen. It won't show again.
    func done<T: HintTip>(_ tip: T) {
        if HintStage.current == T.hintId { HintStage.current = "" }
        if let shownAt = shownAt(T.hintId), now().timeIntervalSince(shownAt) <= Self.actionWindow {
            record(.tipAction, T.hintId)
        }
        forgetShown(T.hintId)
        see(T.hintId)
        tip.invalidate(reason: .actionPerformed)
    }

    func close(_ tip: any Tip) {
        record(.tipDismissed, tip.id)
        if HintStage.current == tip.id { HintStage.current = "" }
        see(tip.id)
        tip.invalidate(reason: .tipClosed)
    }

    func appeared(_ tip: any Tip) { shown(tip.id) }

    private func shown(_ id: String) {
        guard shownThisSession.insert(id).inserted else { return }
        see(id)
        var times = shownTimes()
        times[id] = now().timeIntervalSince1970
        defaults.set(times, forKey: Self.shownAtKey)
        record(.tipShown, id)
    }

    private func shownTimes() -> [String: Double] {
        defaults.dictionary(forKey: Self.shownAtKey) as? [String: Double] ?? [:]
    }

    private func shownAt(_ id: String) -> Date? {
        shownTimes()[id].map(Date.init(timeIntervalSince1970:))
    }

    private func forgetShown(_ id: String) {
        var times = shownTimes()
        guard times.removeValue(forKey: id) != nil else { return }
        defaults.set(times, forKey: Self.shownAtKey)
    }

    private func see(_ id: String) {
        guard seen.insert(id).inserted else { return }
        defaults.set(seen.sorted(), forKey: Self.seenKey)
    }

    static func keyWindowIsPresenting() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }

    private func record(_ name: ClientEventName, _ id: String) {
        pending.append(ClientEvent(name, detail: isHeldOut() ? HintHoldout.detail(id) : id))
        Task { await send() }
    }

    /// Sends what is waiting; what can't reach the server waits for the next hint.
    private func send() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        while !pending.isEmpty {
            let batch = Array(pending.prefix(ReportEventsRequest.maxEvents))
            do {
                try await report(batch)
            } catch {
                return
            }
            pending.removeFirst(min(batch.count, pending.count))
        }
    }
}
