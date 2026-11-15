import Design
import FeatureOnboarding
import Persistence
import SwiftUI
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

/// Settings is one plain vertical scroll on the smallest phone and at the largest text: no row, header or footer
/// reaches past the screen's edges. Laid out in a window, without launching the app; without a server session, so the
/// Account, Apple and Partner sections are the UI tests'.
@MainActor @Suite(.serialized) struct SettingsFitTests {
    nonisolated enum Screen: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case se, seLargestText = "SE, largest text", iPhoneLargestText = "iPhone, largest text"

        var testDescription: String { rawValue }

        @MainActor var phone: HostedLayout.Phone {
            switch self {
            case .se: .se
            case .seLargestText: HostedLayout.Phone.se.largestText()
            case .iPhoneLargestText: HostedLayout.Phone.iPhone.largestText()
            }
        }
    }

    /// An account in memory, signed in, unpaired and not linked to an Apple ID, so every section Settings has
    /// without a partner is on the page, Apple's button included.
    private static func session() -> ServerSession {
        var api = APIClient.offline
        api.account = { () async throws(TransportError) in AccountResponse(userId: UserId("u1"), linked: false) }
        api.authChallenge = { () async throws(TransportError) in
            AuthChallengeResponse(nonce: AuthNonce(String(repeating: "a", count: 43)), expiresAt: 1)
        }
        let record = Mutex(AccountRecord(userID: "u1", deviceID: "d1", expiresAt: .max))
        let accounts = AccountStore(
            load: { () throws(PersistenceError) in ("token", record.withLock { $0 }) },
            save: { (_, new) throws(PersistenceError) in record.withLock { $0 = new } },
            setPaired: { (paired, pairID) throws(PersistenceError) in
                record.withLock {
                    $0.isPaired = paired
                    $0.pairID = pairID
                }
            },
            clear: { () throws(PersistenceError) in })
        let backend = Backend(
            baseURL: URL(string: "https://api.example.dev")!, api: api, accounts: accounts,
            keys: AccountKeyStore(loadOrCreate: { () throws(PersistenceError) in "key" },
                                  clear: { () throws(PersistenceError) in }))
        return ServerSession(backend: backend)
    }

    @Test(arguments: Screen.allCases)
    func nothingReachesPastTheEdges(screen: Screen) async throws {
        UserDefaults.standard.set(true, forKey: "uitestStill")
        let state = HomeState(stores: .live())
        let session = Self.session()
        // The card asks the stubbed server when it appears; a window without a scene never says so: asked here.
        session.appleLink.appeared()
        await session.appleLink.settled()
        let layout = HostedLayout(
            NavigationStack { SettingsView(state: state, erase: {}) }.environment(session), phone: screen.phone)
        layout.settle(1)
        let button = layout.element(id: "signInWithApple")
        #expect(button != nil, "Apple's button is on the page: \(session.appleLink.state)")
        let page = try #require(layout.scrollViews.max { $0.bounds.height < $1.bounds.height }, "no page")
        #expect(page.contentSize.width <= page.bounds.width + 1,
                "the page is \(page.contentSize.width) wide in \(page.bounds.width)")
        let width = layout.bounds.width
        var seen: Set<String> = []
        var outside: [String] = []
        for step in 0..<12 {
            for element in layout.elements() where element.frame.minX < -1 || element.frame.maxX > width + 1 {
                let name = element.label.isEmpty ? element.identifier : element.label
                if seen.insert(name).inserted {
                    outside.append("\(name) \(element.frame.minX)...\(element.frame.maxX)")
                }
            }
            let next = min(page.contentSize.height - page.bounds.height, CGFloat(step + 1) * page.bounds.height * 0.8)
            page.setContentOffset(CGPoint(x: 0, y: max(0, next)), animated: false)
            layout.settle(0.4)
        }
        #expect(outside.isEmpty, "past the edges: \(outside.joined(separator: "; "))")
    }

    /// Apple's button, shown while the account is not linked, asks for a width that grows with the text size.
    @Test(arguments: Screen.allCases)
    func theSignInWithAppleButtonStaysInsideTheScreen(screen: Screen) async throws {
        var api = APIClient.offline
        api.account = { () async throws(TransportError) in AccountResponse(userId: UserId("u1"), linked: false) }
        api.authChallenge = { () async throws(TransportError) in
            AuthChallengeResponse(nonce: AuthNonce(String(repeating: "a", count: 43)), expiresAt: 1)
        }
        let model = AppleLinkModel(api: api)
        model.appeared()
        await model.settled()
        guard case .ready = model.state else {
            Issue.record("the account is not ready to link: \(model.state)")
            return
        }
        let layout = HostedLayout(Page { AppleAccountSection(model: model) }, phone: screen.phone)
        layout.settle(1)
        let button = try #require(layout.element(id: "signInWithApple"), "no button").frame
        let gutters = Space.gutter...(layout.bounds.width - Space.gutter)
        #expect(button.minX >= gutters.lowerBound - 1 && button.maxX <= gutters.upperBound + 1,
                "the button spans \(button.minX)...\(button.maxX) on a \(layout.bounds.width) wide screen")
        #expect(button.height >= Size.button - 1)
    }
}
