import Design
import GamesInterface
import SwiftUI
import Testing
@testable import Billet

/// A game's hint, bar and buttons are one column: every one of them the full width between the gutters, with the
/// same side margins, on the smallest phone and at the largest text; the result card stands between the same
/// gutters. Laid out in a window, without launching the app.
@MainActor @Suite(.serialized) struct GameTrayTests {
    nonisolated enum Screen: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case iPhone, se, iPhoneLargestText = "iPhone, largest text", seLargestText = "SE, largest text"

        var testDescription: String { rawValue }

        @MainActor var phone: HostedLayout.Phone {
            switch self {
            case .iPhone: .iPhone
            case .se: .se
            case .iPhoneLargestText: HostedLayout.Phone.iPhone.largestText()
            case .seLargestText: HostedLayout.Phone.se.largestText()
            }
        }
    }

    /// Feed at the end of a meal: a hint, the bowl's bar and both buttons.
    private static let feed = GameTray(
        hint: "Sweep up the crumbs, or feed Tofu as it is",
        bar: GameMeter(value: 1.1, label: "Bowl", detail: "40 / 36 g"), symbol: "fork.knife",
        action: "Feed", assist: "Clean up", act: {}, assistAct: {})

    /// Brush mid-way: a short hint over the bar alone.
    private static let brush = GameTray(
        hint: "Other way: with the fur, head to tail", bar: GameMeter(value: 0.53, label: "Groomed", detail: nil),
        symbol: "comb.fill", action: nil, assist: nil, act: {}, assistAct: {})

    private func frame(_ layout: HostedLayout, _ id: String) throws -> CGRect {
        try #require(layout.element(id: id), "no \(id)").frame
    }

    private func gutters(_ layout: HostedLayout) -> ClosedRange<CGFloat> {
        Space.gutter...(layout.bounds.width - Space.gutter)
    }

    @Test(arguments: Screen.allCases)
    func theFeedTrayIsOneColumnBetweenTheGutters(screen: Screen) throws {
        let layout = HostedLayout(Self.feed, phone: screen.phone)
        let frames = try ["game.hint", "game.bar", "game.action", "game.assist"].map { try frame(layout, $0) }
        let gutters = gutters(layout)
        for (id, frame) in zip(["hint", "bar", "action", "assist"], frames) {
            #expect(abs(frame.minX - gutters.lowerBound) < 1, "\(id) at \(frame.minX), not \(gutters.lowerBound)")
            #expect(abs(frame.maxX - gutters.upperBound) < 1, "\(id) ends at \(frame.maxX), not \(gutters.upperBound)")
        }
        for (above, below) in zip(frames, frames.dropFirst()) { #expect(above.maxY <= below.minY + 1) }
    }

    @Test(arguments: Screen.allCases)
    func theBrushHintIsAsWideAsItsBar(screen: Screen) throws {
        let layout = HostedLayout(Self.brush, phone: screen.phone)
        let hint = try frame(layout, "game.hint")
        let bar = try frame(layout, "game.bar")
        #expect(abs(hint.minX - bar.minX) < 1, "hint \(hint) against bar \(bar)")
        #expect(abs(hint.width - bar.width) < 1, "hint \(hint) against bar \(bar)")
        #expect(abs(bar.minX - Space.gutter) < 1)
    }

    @Test(arguments: Screen.allCases)
    func theResultCardStandsBetweenTheSameGutters(screen: Screen) throws {
        let result = GameResult(game: .feed, score: 90, grams: 40, tooMuch: true)
        let layout = HostedLayout(ResultToast(result: result, again: {}, done: {}), phone: screen.phone)
        let again = try #require(layout.element(label: "Play again")).frame
        let done = try #require(layout.element(label: "Back to the room")).frame
        // The buttons fill the card's inside, side by side or stacked: together they say where the card stands.
        let inside = (Space.gutter + CardMetrics.padding)...(layout.bounds.width - Space.gutter - CardMetrics.padding)
        #expect(abs(min(again.minX, done.minX) - inside.lowerBound) < 1, "again \(again), done \(done)")
        #expect(abs(max(again.maxX, done.maxX) - inside.upperBound) < 1, "again \(again), done \(done)")
    }
}
