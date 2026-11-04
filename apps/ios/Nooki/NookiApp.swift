import Transport
import SwiftUI

@main
struct NookiApp: App {
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var session: ServerSession?
    @State private var onboarding: OnboardingFlow

    init() {
        let session: ServerSession? = Self.isHostingTests ? nil : Backend.live().map { ServerSession(backend: $0) }
        let client: OnboardingClient = session?.onboarding ?? .offline
        let api: APIClient = session?.api ?? .offline
        let canInvite = session.map { !$0.isPaired } ?? false
        _session = State(initialValue: session)
        _onboarding = State(initialValue: OnboardingFlow(
            client: client, report: api.reportEvents, queue: AnswerQueue(), canInvite: canInvite,
            coatChanged: { CatRoom.forgetMochi() }))
    }

    var body: some Scene {
        WindowGroup {
            if Self.isHostingTests {
                // The unit tests run on the main actor; the room would keep it busy drawing the whole time.
                Color.black
            } else {
                HomeView()
                    // A new coat loads Mochi again, so the room is built anew around her.
                    .id(onboarding.wornCoat)
                    .preferredColorScheme(.dark)
                    .environment(session)
                    .overlay {
                        if !onboarding.isFinished {
                            OnboardingView(flow: onboarding, pairing: session?.pairing)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: onboarding.isFinished)
                    // Silent: the account key in the iCloud Keychain is the account, so there is nothing to ask.
                    .task { session?.signIn.appeared() }
            }
        }
    }

    /// The app was launched to host NookiTests.
    private static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
