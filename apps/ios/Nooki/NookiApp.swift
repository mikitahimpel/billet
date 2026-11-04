import SwiftUI

@main
struct NookiApp: App {
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var session: ServerSession? =
        isHostingTests ? nil : Backend.live().map { ServerSession(backend: $0) }

    var body: some Scene {
        WindowGroup {
            if Self.isHostingTests {
                // The unit tests run on the main actor; the room would keep it busy drawing the whole time.
                Color.black
            } else {
                HomeView()
                    .preferredColorScheme(.dark)
                    .environment(session)
                    // Silent: the account key in the iCloud Keychain is the account, so there is nothing to ask.
                    .task { session?.signIn.appeared() }
            }
        }
    }

    /// The app was launched to host NookiTests.
    private static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
