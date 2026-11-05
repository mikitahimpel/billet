import Transport
import SwiftUI

@main
struct NookiApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var session: ServerSession?
    @State private var onboarding: OnboardingFlow
    @State private var hints: Hints
    @State private var home: HomeState

    init() {
        NavigationBarStyle.apply()
        let session: ServerSession? = Self.isHostingTests ? nil : Backend.live().map { ServerSession(backend: $0) }
        let client: OnboardingClient = session?.onboarding ?? .offline
        let api: APIClient = session?.api ?? .offline
        let canInvite = session.map { !$0.isPaired } ?? false
        _session = State(initialValue: session)
        Hints.configure()
        CatProfile.moveToAppGroup()
        _hints = State(initialValue: Hints(report: api.reportEvents))
        _onboarding = State(initialValue: OnboardingFlow(
            client: client, report: api.reportEvents, queue: AnswerQueue(), canInvite: canInvite,
            hasServer: session != nil, asksTogetherSince: true,
            togetherSinceChosen: { day in
                let profile = CoupleStore()
                profile.update(names: profile.couple.names ?? [:], togetherSince: day)
                NotificationCenter.default.post(name: .coupleChanged, object: nil)
            },
            requestPushes: { await DrawingSync.requestPushes(asking: true) },
            coatChanged: { CatRoom.forgetMochi() }))
        _home = State(initialValue: HomeState(stores: .live()))
    }

    var body: some Scene {
        WindowGroup {
            if Self.isHostingTests {
                // The unit tests run on the main actor; the room would keep it busy drawing the whole time.
                Color.black
            } else {
                HomeView(state: $home)
                    // A new coat loads Mochi again, so the room is built anew around her.
                    .id(onboarding.wornCoat)
                    .preferredColorScheme(.dark)
                    .environment(session)
                    .environment(hints)
                    .hintStyle(hints)
                    .overlay {
                        if !onboarding.isFinished {
                            OnboardingView(
                                flow: onboarding, pairing: session?.pairing, signedIn: session?.isSignedIn ?? false,
                                inviteBase: session?.baseURL, alreadyPaired: session?.isPaired ?? false,
                                paired: { session?.pairingFinished() })
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: onboarding.isFinished)
                    .onOpenURL { url in
                        if case .invite(let code) = DeepLink(url: url) { onboarding.join(code: code) }
                    }
                    // Silent: the account key in the iCloud Keychain is the account, so there is nothing to ask.
                    .task { session?.signIn.appeared() }
                    .onChange(of: onboarding.isFinished, initial: true) { hints.onboardingFinished(onboarding.isFinished) }
                    .onChange(of: canInvite, initial: true) { hints.canInvite(canInvite) }
                    .onChange(of: session?.isPaired == true, initial: true) { _, paired in
                        if paired { hints.done(InviteHint()) }
                    }
            }
        }
    }

    /// Someone to invite: signed in, and not paired yet.
    private var canInvite: Bool {
        guard let session else { return false }
        return session.isSignedIn && !session.isPaired
    }

    /// The app was launched to host NookiTests.
    private static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
