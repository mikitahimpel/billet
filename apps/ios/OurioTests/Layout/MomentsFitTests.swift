import Design
import MomentsInterface
import SwiftUI
import Testing
@testable import Billet

/// With no photo yet, Moments says what to do and offers the first one, whole, on the smallest phone and at the
/// largest text: the words are never cut to one line, and what is taller than the tab scrolls. Laid out in a window,
/// without launching the app.
@MainActor @Suite(.serialized) struct MomentsFitTests {
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

        var largestText: Bool { self == .iPhoneLargestText || self == .seLargestText }
    }

    @Test(arguments: Screen.allCases)
    func theEmptyStateIsWholeAndReachable(screen: Screen) throws {
        UserDefaults.standard.set(true, forKey: "uitestStill")
        let state = HomeState(stores: .live(events: .none))
        for moment in state.moments.moments { state.moments.delete(moment) }
        state.tab = .moments
        let layout = HostedLayout(MomentsView(state: state), phone: screen.phone)
        layout.settle(1)
        // The first layout of the suite can take a moment longer to get its elements.
        for _ in 0..<8 where layout.element(label: "Your first moment") == nil { layout.settle(0.5) }
        let window = layout.bounds
        let title = try #require(layout.element(label: "Your first moment"), "no title").frame
        let add = try #require(layout.element(id: "moments.add"), "no add button").frame
        for (what, frame) in [("title", title), ("button", add)] {
            #expect(frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1, "the \(what) is inside the window")
        }
        #expect(abs(title.midX - window.midX) <= 2, "the title is centred")
        #expect(add.minY >= title.maxY, "the button is under the words")
        // At the largest text the title alone takes two lines, so the state is taller than the tab and scrolls;
        // squeezed into the tab instead, its texts would be cut to one line each.
        let page = try #require(layout.scrollViews.first, "the empty state scrolls")
        let insets = page.adjustedContentInset
        let visible = page.bounds.height - insets.top - insets.bottom
        let scrolls = page.contentSize.height > visible + 1
        #expect(scrolls == screen.largestText, "\(page.contentSize.height) of content in \(visible)")
        if scrolls {
            page.setContentOffset(CGPoint(x: 0, y: page.contentSize.height - page.bounds.height + insets.bottom),
                                  animated: false)
            layout.settle()
        }
        let end = try #require(layout.element(id: "moments.add"), "no add button at the end").frame
        #expect(end.maxY <= window.maxY - insets.bottom + 1, "the button is on screen at the end")
        #expect(end.height >= Size.button - 1, "the button keeps its height")
    }

    /// The wall card's "Add photo" pill keeps its words on one line beside the header, on the smallest phone too.
    @Test(arguments: [Screen.se, Screen.iPhone])
    func theWallPillIsOneLine(screen: Screen) throws {
        let strip = WallStrip(store: MomentStore(), pick: .constant(nil)).padding(Space.l)
        let layout = HostedLayout(strip, phone: screen.phone)
        layout.settle(0.5)
        let pill = try #require(layout.element(id: "wallAddPhoto"), "no Add photo pill").frame
        #expect(pill.height <= Size.control + 1, "the pill is \(pill.height) tall")
        #expect(pill.maxX <= layout.bounds.maxX + 1, "the pill is inside the window")
    }
}
