import Transport
import SwiftUI

@main
struct NookiApp: App {
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var session: ServerSession?
    @State private var onboarding: OnboardingFlow

    init() {
        let session = Self.isHostingTests ? nil : Backend.live().map { ServerSession(backend: $0) }
        _session = State(initialValue: session)
        _onboarding = State(initialValue: OnboardingFlow(
            client: session?.onboarding ?? .offline,
            report: session?.api.reportEvents ?? { (_) async throws(TransportError) in throw .network("offline") },
            queue: AnswerQueue(),
            canInvite: session.map { !$0.isPaired } ?? false))
    }

    var body: some Scene {
        WindowGroup {
            if Self.isHostingTests {
                // The unit tests run on the main actor; the room would keep it busy drawing the whole time.
                Color.black
            } else {
                HomeView()
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
