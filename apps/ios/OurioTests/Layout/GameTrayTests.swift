import Design
import GamesInterface
import SwiftUI
import Testing
@testable import Billet

/// A game's hint, bar and buttons are one column on one tray: every one of them the tray's full inner width, the main
/// action taller than the quiet one under it, on the smallest phone and at the largest text; the result stands on the
/// same tray, its earnings one row as wide as its buttons. Laid out in a window, without launching the app.
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

    /// The tray stands between the gutters; its content sits the card's padding inside them.
    private func inside(_ layout: HostedLayout) -> ClosedRange<CGFloat> {
        (Space.gutter + CardMetrics.padding)...(layout.bounds.width - Space.gutter - CardMetrics.padding)
    }

    @Test(arguments: Screen.allCases)
    func theFeedTrayIsOneColumnInsideTheTray(screen: Screen) throws {
        let layout = HostedLayout(Self.feed, phone: screen.phone)
        let ids = ["hint", "bar", "action", "assist"]
        let frames = try ids.map { try frame(layout, "game.\($0)") }
        let inside = inside(layout)
        for (id, frame) in zip(ids, frames) {
            #expect(abs(frame.minX - inside.lowerBound) < 1, "\(id) at \(frame.minX), not \(inside.lowerBound)")
            #expect(abs(frame.maxX - inside.upperBound) < 1, "\(id) ends at \(frame.maxX), not \(inside.upperBound)")
        }
        for (above, below) in zip(frames, frames.dropFirst()) { #expect(above.maxY <= below.minY + 1) }
    }

    @Test(arguments: Screen.allCases)
    func theMainActionIsTallerThanTheQuietOne(screen: Screen) throws {
        let layout = HostedLayout(Self.feed, phone: screen.phone)
        let action = try frame(layout, "game.action")
        let assist = try frame(layout, "game.assist")
        #expect(action.height >= Size.button - 1)
        #expect(assist.height < action.height, "assist \(assist) against action \(action)")
    }

    @Test(arguments: Screen.allCases)
    func theBrushHintIsAsWideAsItsBar(screen: Screen) throws {
        let layout = HostedLayout(Self.brush, phone: screen.phone)
        let hint = try frame(layout, "game.hint")
        let bar = try frame(layout, "game.bar")
        #expect(abs(hint.minX - bar.minX) < 1, "hint \(hint) against bar \(bar)")
        #expect(abs(hint.width - bar.width) < 1, "hint \(hint) against bar \(bar)")
        #expect(abs(bar.minX - inside(layout).lowerBound) < 1)
    }

    @Test(arguments: Screen.allCases)
    func theResultStandsOnTheSameTray(screen: Screen) throws {
        let result = GameResult(game: .feed, score: 90, grams: 40, tooMuch: true)
        let layout = HostedLayout(ResultToast(result: result, again: {}, done: {}), phone: screen.phone)
        let again = try #require(layout.element(label: "Play again")).frame
        let done = try #require(layout.element(label: "Back to the room")).frame
        let care = try frame(layout, "game.care")
        let coins = try frame(layout, "game.coins")
        let inside = inside(layout)
        for (id, frame) in [("again", again), ("done", done)] {
            #expect(abs(frame.minX - inside.lowerBound) < 1, "\(id) \(frame)")
            #expect(abs(frame.maxX - inside.upperBound) < 1, "\(id) \(frame)")
        }
        // The earnings fill the same inner width, side by side at one size or stacked.
        #expect(abs(min(care.minX, coins.minX) - inside.lowerBound) < 1, "care \(care), coins \(coins)")
        #expect(abs(max(care.maxX, coins.maxX) - inside.upperBound) < 1, "care \(care), coins \(coins)")
        #expect(abs(care.width - coins.width) < 1 && abs(care.height - coins.height) < 1)
        #expect(done.maxY <= again.minY + 1, "the main action comes first")
        #expect(max(care.maxY, coins.maxY) <= done.minY + 1)
    }
}
