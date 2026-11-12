import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import Transport
import SwiftUI
import Design
import UsInterface

@main
struct OurioApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var session: ServerSession?
    @State private var onboarding: OnboardingFlow
    @State private var hints: Hints
    @State private var home: HomeState

    init() {
        #if LABS_YES
        // Metal reads it when it first draws; Labs > Performance switches it, and it starts off.
        if PerfLabMachine.State.saved(in: .standard).isOn(.metalHud) { setenv("MTL_HUD_ENABLED", "1", 1) }
        #endif
        NavigationBarStyle.prepare()
        // Date card pictures are immutable files the cards fetch through the shared session; room for all of them.
        URLCache.shared = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        let parts = Self.assemble()
        _session = State(initialValue: parts.session)
        _hints = State(initialValue: parts.hints)
        _onboarding = State(initialValue: parts.onboarding)
        _home = State(initialValue: parts.home)
    }

    /// Everything a launch builds from what is on the phone; building it again after the account is deleted is a
    /// first launch.
    private struct Parts {
        let session: ServerSession?
        let hints: Hints
        let onboarding: OnboardingFlow
        let home: HomeState
    }

    private static func assemble() -> Parts {
        let session: ServerSession? = Self.isHostingTests ? nil : Backend.live().map { ServerSession(backend: $0) }
        let client: OnboardingClient = session?.onboarding ?? .offline
        let api: APIClient = session?.api ?? .offline
        let canInvite = session.map { !$0.isPaired } ?? false
        Hints.configure()
        CatProfile.moveToAppGroup()
        let hints = Hints(report: api.reportEvents)
        let onboarding = OnboardingFlow(
            client: client, report: api.reportEvents, queue: AnswerQueue(), canInvite: canInvite,
            hasServer: session != nil, asksTogetherSince: true,
            togetherSinceChosen: { day in
                let profile = CoupleStore()
                profile.update(names: profile.couple.names ?? [:], togetherSince: day)
                NotificationCenter.default.post(name: .coupleChanged, object: nil)
            },
            requestPushes: { await DrawingSync.requestPushes(asking: true) },
            nameChosen: { name in
                let profile = CoupleStore()
                var names = profile.couple.names ?? [:]
                names[profile.couple.viewer] = name
                profile.update(names: names, togetherSince: profile.couple.togetherSince)
                NotificationCenter.default.post(name: .coupleChanged, object: nil)
            },
            coatChanged: { CatRoom.forgetMochi() })
        return Parts(session: session, hints: hints, onboarding: onboarding, home: HomeState(stores: .live()))
    }

    private func startOver() {
        let parts = Self.assemble()
        session = parts.session
        hints = parts.hints
        onboarding = parts.onboarding
        home = parts.home
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
                    .environment(\.startOver, StartOver { startOver() })
                    .hintStyle(hints)
                    .overlay {
                        if !onboarding.isFinished {
                            OnboardingView(
                                flow: onboarding, pairing: session?.pairing, signedIn: session?.isSignedIn ?? false,
                                inviteBase: session?.baseURL, alreadyPaired: session?.isPaired ?? false,
                                paired: { session?.pairingFinished() },
                                demoPartner: demoPartnerPairing)
                                // Drawn over Home, which hides itself from VoiceOver only while its splash shows;
                                // a modal view is the only one VoiceOver reads.
                                .accessibilityAddTraits(.isModal)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: onboarding.isFinished)
                    .onOpenURL { url in
                        if case .invite(let code) = DeepLink(url: url) { onboarding.join(code: code) }
                    }
                    // Silent: the account key in the iCloud Keychain is the account, so there is nothing to ask.
                    .task(id: session.map(ObjectIdentifier.init)) {
                        session?.signIn.appeared()
                        await session?.refreshDateCatalog()
                        await session?.refreshGuessCatalog()
                    }
                    .task(id: session?.isSignedIn) { await session?.checkDemoPartner() }
                    .onChange(of: onboarding.isFinished, initial: true) { hints.onboardingFinished(onboarding.isFinished) }
            }
        }
    }

    /// Built on its own: written inline, the compiler cannot check `body`.
    private var demoPartnerPairing: (() -> Void)? {
        // Dev server only, and only in builds that are not the App Store's.
        guard session?.demoPartner == false, Self.isPreReleaseBuild else { return nil }
        return { pairWithDemoPartner() }
    }

    private func pairWithDemoPartner() {
        Task { try? await session?.pairWithDemoPartner() }
    }

    private static var isPreReleaseBuild: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    private static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
