import FeatureOnboarding
import SwiftUI

@main
struct NookiApp: App {
    /// Nil when the build has no server; the app then keeps everything on the phone.
    @State private var signIn: AnonymousSignInModel? = Backend.live().map {
        AnonymousSignInModel(api: $0.api, keys: $0.keys, accounts: $0.accounts)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .environment(signIn)
                // Silent: the account key in the iCloud Keychain is the account, so there is nothing to ask.
                .task { signIn?.appeared() }
        }
    }
}
