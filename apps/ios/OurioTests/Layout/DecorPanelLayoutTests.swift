import DecorInterface
import Design
import SwiftUI
import Testing
@testable import Billet

/// The Decorate panel is one card that hugs what it holds: the title row, the hint, the closet and the action row,
/// each the kit's spacing from the next, its tiles one size, its actions as wide as the title row, its foot on the
/// safe area. Laid out in a window over the bottom of the screen, as Home lays it over the room.
@MainActor @Suite(.serialized) struct DecorPanelLayoutTests {
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

    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        let screen: Screen
        let pieces: Int

        var testDescription: String { "\(screen.rawValue), \(pieces) in the closet" }

        static let all: [Case] = Screen.allCases.flatMap { screen in [0, 1, 2, 7].map { Case(screen: screen, pieces: $0) } }
    }

    private static let bought = ["lamp", "rug", "yarn", "print", "lantern", "monstera", "teatable"]

    private func host(_ test: Case) -> HostedLayout {
        UserDefaults.standard.set(true, forKey: "uitestStill")
        let state = HomeState(stores: .live(events: .none))
        state.decor.send(.loaded(DecorLayout(stored: Set(Self.bought))))
        state.decor.send(.owned(Set(Self.bought.prefix(test.pieces))))
        state.decor.send(.opened(item: nil))
        let view = Color.clear.overlay(alignment: .bottom) { DecorPanel(state: state) {} }
        let layout = HostedLayout(view, phone: test.screen.phone)
        layout.settle(0.5)
        // The first window after accessibility comes on can list its elements a pass or two late.
        for _ in 0..<20 where layout.element(id: "decorDone") == nil || layout.element(id: "decorReset") == nil {
            layout.settle(0.25)
        }
        return layout
    }

    private func frame(_ layout: HostedLayout, _ id: String) throws -> CGRect {
        try #require(layout.element(id: id), "no \(id) among \(layout.elements().map(\.identifier).filter { !$0.isEmpty })").frame
    }

    @Test(arguments: Case.all)
    func thePanelHugsItsSectionsAtTheKitsSpacing(test: Case) throws {
        let layout = host(test)
        let title = try #require(layout.element(label: "Decorate"), "no title").frame
        let done = try frame(layout, "decorDone")
        let hint = try #require(layout.element(label: "Tap a piece, or place one below."), "no hint").frame
        let reset = try frame(layout, "decorReset")
        let tiles = layout.elements().filter { $0.identifier.hasPrefix("decorCloset.") }.map(\.frame)
        // The panel's own frame takes in the card's shadow, so the card is measured by what it holds.
        let inside = (Space.l + CardMetrics.padding)...(layout.bounds.width - Space.l - CardMetrics.padding)
        let contentTop = min(title.minY, done.minY)
        let cardBottom = reset.maxY + CardMetrics.padding

        #expect(contentTop - CardMetrics.padding >= layout.window.safeAreaInsets.top - 1, "the card's top \(contentTop) stays under the status bar")
        #expect(abs(cardBottom + Space.m - (layout.bounds.maxY - layout.safeBottom)) < 1, "the card's foot \(cardBottom) stands on the safe area")
        #expect(abs(done.maxX - inside.upperBound) < 1, "Done \(done) ends at \(inside.upperBound)")
        #expect(abs(title.minX - inside.lowerBound) < 1, "the title \(title) starts at \(inside.lowerBound)")
        // At the accessibility sizes Done takes the width under the hint; otherwise the hint runs under Done's row.
        // There Done's frame also reaches some points past its capsule, so what borders it is checked to that slack.
        let largest = test.screen.phone.dynamicType.isAccessibilitySize
        let doneSlack: CGFloat = largest ? 6 : 1
        let headerBottom = max(hint.maxY, done.maxY)
        if largest {
            #expect(abs(hint.minY - title.maxY - Space.s) < 1, "title to hint: \(hint.minY - title.maxY)")
            #expect(abs(done.minY - hint.maxY - Space.s) <= doneSlack, "hint to Done: \(done.minY - hint.maxY)")
        } else {
            #expect(abs(hint.minY - done.maxY - Space.s) < 1, "title row to hint: \(hint.minY - done.maxY)")
        }

        let closetTop: CGFloat
        let closetBottom: CGFloat
        if test.pieces == 0 {
            // The closet's own box: in the first window of a run the iOS 26.2 Simulator leaves the note out of the
            // accessibility tree, though it is laid out and drawn.
            let scroll = try #require(layout.scrollViews.first, "no closet")
            let empty = scroll.convert(scroll.bounds, to: nil)
            #expect(empty.height > Size.button, "the empty note \(empty) is shown")
            closetTop = empty.minY
            closetBottom = empty.maxY
        } else {
            try #require(tiles.count >= min(test.pieces, 2), "tiles: \(tiles)")
            closetTop = tiles.map(\.minY).min() ?? 0
            closetBottom = tiles.map(\.maxY).max() ?? 0
            let first = tiles[0]
            for tile in tiles {
                #expect(abs(tile.width - first.width) < 1 && abs(tile.height - first.height) < 1, "tile \(tile) against \(first)")
                #expect(tile.minX >= inside.lowerBound - 1 && tile.maxX <= inside.upperBound + 1, "tile \(tile) inside \(inside)")
            }
            let rowWidth = tiles.filter { abs($0.minY - first.minY) < 1 }.map(\.maxX).max().map { $0 - first.minX } ?? 0
            if test.pieces >= 2 { #expect(abs(rowWidth - (inside.upperBound - inside.lowerBound)) < 1, "a row \(rowWidth) fills the card") }
        }
        let slack: CGFloat = 1
        let topGap = closetTop - headerBottom
        #expect(abs(topGap - Space.m) <= max(slack, doneSlack), "header to closet: \(topGap)")
        let scroll = layout.scrollViews.first { $0.contentSize.height > $0.bounds.height + 1 }
        if test.pieces > 2 { #expect(scroll != nil, "a long closet scrolls") }
        // At the largest text a short closet may scroll: the empty note alone is taller than the cap.
        if test.pieces <= 2, !largest { #expect(scroll == nil, "a short closet does not scroll") }
        if let scroll {
            let shown = scroll.convert(scroll.bounds, to: nil)
            #expect(shown.height <= DecorPanel.closetCap + 1, "the closet \(shown) stays under its cap")
            #expect(abs(reset.minY - shown.maxY - Space.l) < 1, "closet \(shown) to actions \(reset)")
        } else {
            let bottomGap = reset.minY - closetBottom
            #expect(abs(bottomGap - Space.l) <= slack, "closet to actions: \(bottomGap)")
        }
        #expect(abs(reset.minX - inside.lowerBound) < 1 && abs(reset.maxX - inside.upperBound) < 1, "Reset \(reset) spans \(inside)")
    }
}
