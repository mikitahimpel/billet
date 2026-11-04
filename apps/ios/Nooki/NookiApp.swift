import SwiftUI

@main
struct NookiApp: App {
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var session: ServerSession? = Backend.live().map(ServerSession.init)

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .environment(session)
                // Silent: the account key in the iCloud Keychain is the account, so there is nothing to ask.
                .task { session?.signIn.appeared() }
        }
    }
}
