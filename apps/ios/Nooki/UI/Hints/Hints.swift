import Observation
import SwiftUI
import TipKit
import Transport
import Wire

/// The hints after the onboarding (`HintTips.swift`): sets TipKit up, marks each hint done and reports what the hints
/// do. Shared through the environment with the views the hints point at.
@MainActor
@Observable
final class Hints {
    /// "Show hints again" in Settings: the hints start over on the next launch.
    static let resetKey = "hintsReset"
    /// Labs: every hint shows at once, whatever its rules, from the next launch.
    static let showAllKey = "hintsShowAll"

    /// Every hint, in the order they come.
    static let all: [any HintTip.Type] = [
        PetHint.self, AddHint.self, MomentsHint.self, ShopHint.self, RoomsHint.self, TreatHint.self, InviteHint.self,
    ]

    @ObservationIgnored private let report: @Sendable ([ClientEvent]) async throws(TransportError) -> Void
    @ObservationIgnored private var pending: [ClientEvent] = []
    @ObservationIgnored private var sending = false
    /// Hints already reported as shown since launch, so a popover drawn again isn't counted twice.
    @ObservationIgnored private var shown: Set<String> = []

    init(report: @escaping @Sendable ([ClientEvent]) async throws(TransportError) -> Void) {
        self.report = report
    }

    /// Starts TipKit, once, before any view asks for a hint. At most one new hint an hour.
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: resetKey)
        }
        if defaults.bool(forKey: showAllKey) { Tips.showAllTipsForTesting() }
        #if DEBUG
        // For screenshots: `-hint treat` shows only that hint, whatever its rules.
        if let only = defaults.string(forKey: "hint"), let hint = all.first(where: { $0.hintId == only }) {
            Tips.showTipsForTesting([hint])
            Tips.hideTipsForTesting(all.filter { $0.hintId != only })
        }
        // The UI tests tap through the app; a popover would take their first tap.
        if defaults.bool(forKey: "uitestNoHints") { Tips.hideAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.hourly)])
    }

    func onboardingFinished(_ finished: Bool) {
        PetHint.onboarded = finished
    }

    func canInvite(_ can: Bool) {
        InviteHint.canInvite = can
    }

    /// With a single room there is no switch to point at: its hint is put away and the next one follows.
    func roomChoice(_ hasRoomChoice: Bool) {
        if !hasRoomChoice { done(RoomsHint()) }
    }

    /// The person did the thing the hint points at, whether or not it was on screen. Later hints may follow.
    func done<T: HintTip>(_ tip: T) {
        guard !tip.isInvalidated else { return }
        if tip.shouldDisplay { record(.tipAction, T.hintId) }
        tip.invalidate(reason: .actionPerformed)
        Task { await T.done.donate() }
    }

    /// The hint's own X.
    func close(_ tip: any Tip) {
        record(.tipDismissed, tip.id)
        tip.invalidate(reason: .tipClosed)
        Task { await Self.doneEvent(for: tip)?.donate() }
    }

    /// A hint came on screen.
    func appeared(_ tip: any Tip) {
        guard shown.insert(tip.id).inserted else { return }
        record(.tipShown, tip.id)
    }

    private static func doneEvent(for tip: any Tip) -> Tips.Event<Tips.EmptyDonation>? {
        (type(of: tip) as? any HintTip.Type)?.done
    }

    private func record(_ name: ClientEventName, _ id: String) {
        pending.append(ClientEvent(name, detail: id))
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

private extension Tip {
    var isInvalidated: Bool {
        if case .invalidated = status { return true }
        return false
    }
}
