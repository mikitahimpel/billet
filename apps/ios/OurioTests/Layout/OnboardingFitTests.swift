import FeatureOnboarding
import RoomInterface
import SwiftUI
import Testing
import Transport
import Wire
@testable import Billet

private struct StubScenery: OnboardingScenery {
    func heroBackdrop() -> AnyView { AnyView(Color.clear) }
    func warmBackdrop() -> AnyView { AnyView(Color.clear) }
    func heroStage(coat: RoomInterface.CatCoat, time: TimeInterval, pokedAt: TimeInterval?, moving: Bool) -> AnyView {
        AnyView(Color.clear)
    }
}

/// The onboarding pages share one bottom: the primary action sits at the same height on every page, whatever the page
/// above it holds, and the welcome fits the phone and its terms can be read clear of the actions, on the smallest
/// phone and at the largest text. Laid out in a window, without launching the app.
@MainActor @Suite(.serialized) struct OnboardingFitTests {
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

    private func layout(
        page: Int = 0, open: String? = nil, joining: Bool = false, phone: HostedLayout.Phone
    ) -> HostedLayout {
        let defaults = UserDefaults(suiteName: "onboarding-fit-\(UUID().uuidString)")!
        defaults.set(false, forKey: "onboardingDone")
        defaults.set(joining, forKey: "onboardingJoining")
        defaults.set(page, forKey: "onboardingPage")
        if let open { defaults.set(open, forKey: "onboardingOpen") }
        let flow = OnboardingFlow(
            client: .offline, report: { _ in }, queue: AnswerQueue(), defaults: defaults, catNames: defaults,
            canInvite: false, hasServer: false, asksTogetherSince: true)
        let layout = HostedLayout(OnboardingView(flow: flow, pairing: nil, scenery: StubScenery()), phone: phone)
        // The welcome's actions fade in as its script plays; the other pages have nothing to wait for.
        layout.settle(page == 0 && open == nil ? 4 : 0.6)
        return layout
    }

    private func primary(_ layout: HostedLayout, _ name: String) throws -> CGRect {
        try #require(layout.element(id: "onboarding.primary"), "\(name) has no primary action").frame
    }

    @Test(arguments: [Screen.iPhone, .se])
    func thePrimaryActionSitsAtTheSameHeightOnEveryPage(screen: Screen) throws {
        let phone = screen.phone
        var frames: [String: CGRect] = [:]
        var safeBottom: CGFloat = 0
        for page in 0...3 {
            let hosted = layout(page: page, phone: phone)
            frames["page \(page)"] = try primary(hosted, "page \(page)")
            if page == 0 { safeBottom = hosted.safeBottom }
        }
        frames["coat"] = try primary(layout(page: 1, open: "catCoat", phone: phone), "the coat step")
        let welcome = try #require(frames["page 0"])
        #expect(welcome.maxY <= phone.size.height)
        // Nothing reserved under it: the gap to the window's edge is the safe area and one spacing token.
        #expect(phone.size.height - welcome.maxY - safeBottom < 26, "the primary sits on the bottom")
        for (name, frame) in frames {
            #expect(abs(frame.maxY - welcome.maxY) <= 1, "\(name)'s primary is where the welcome's is")
        }
    }

    @Test(arguments: Screen.allCases)
    func theWelcomeFitsAndItsTermsClearTheActions(screen: Screen) throws {
        let name = screen.rawValue
        let layout = layout(phone: screen.phone)
        let window = layout.bounds
        let title = try #require(layout.element(label: "A cat for the two of you"), "no title on \(name)").frame
        let go = try primary(layout, name)
        for (what, frame) in [("title", title), ("button", go)] {
            #expect(frame.minX >= window.minX && frame.maxX <= window.maxX, "\(name): the \(what) is inside the window")
        }
        #expect(abs(title.midX - window.midX) <= 2, "\(name): the title is centred")
        #expect(go.maxY <= window.maxY, "\(name): the button is on screen")

        // At the largest text the welcome scrolls; the terms are read where they come into view.
        layout.scrollToEnd()
        let terms = try #require(layout.element(id: "welcome.terms"), "no terms on \(name)").frame
        #expect(terms.minY >= 0, "\(name): the terms are on screen")
        #expect(terms.maxY <= go.minY, "\(name): the terms sit above the button")
    }

    /// The keyboard's height with its suggestion bar, as each phone draws it.
    private func keyboard(_ screen: Screen) -> CGFloat { screen == .se ? 260 : 336 }

    @Test(arguments: [Screen.iPhone, .se])
    func theInviteCodeAndItsButtonsStayClearOfJoinUnderTheKeyboard(screen: Screen) throws {
        let name = screen.rawValue
        let layout = layout(page: 1, joining: true, phone: screen.phone)
        layout.raiseKeyboard(keyboard(screen))
        let join = try primary(layout, name)
        let code = try #require(layout.element(id: "join.code"), "no code field on \(name)").frame
        let rule = try #require(layout.element(id: "join.rule"), "no code rule on \(name)").frame
        #expect(join.maxY <= screen.phone.size.height - keyboard(screen) + 1, "\(name): Join sits on the keyboard")
        #expect(code.minY >= layout.window.safeAreaInsets.top, "\(name): the code field \(code) is under the status bar")
        #expect(code.maxY <= join.minY, "\(name): the code field \(code) clears Join \(join)")
        #expect(rule.maxY <= join.minY, "\(name): the line under the buttons \(rule) clears Join \(join)")
    }
}
