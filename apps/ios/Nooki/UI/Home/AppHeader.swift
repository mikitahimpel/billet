import SwiftUI
import Design

/// The one header of every tab (World, Moments, Shop, Us), in the same place on each: the Inbox and "How are you?"
/// top-left; top-right the coins, then the couple's avatars in the corner, which open the profile. Nothing else sits
/// in it.
struct AppHeader: View {
    let state: HomeState
    /// Wipes everything saved on this phone and starts the app over, from the profile's settings.
    var erase: () -> Void
    @State private var pairing = false
    @State private var checkingIn = false
    @AppStorage(PlusPass.key) private var plus = false
    @Environment(ServerSession.self) private var session: ServerSession?

    var body: some View {
        // One container for the header's glass, as the tab bar has, so it is sampled together.
        GlassGroup(spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.s + 2) {
                InboxButton(unread: session?.inbox.unread ?? 0) { state.showsInbox = true }
                MoodHeaderButton(state: state) { checkingIn = true }

                Spacer(minLength: 0)

                Button { state.shop.askForCoins() } label: { CoinPill(coins: state.shop.coins) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("\(state.shop.coins) coins")
                    .accessibilityHint("Shows your coins, how to get more and where they went")
                    .accessibilityIdentifier("coins")

                CoupleButton(state: state, plus: plus) { state.showsProfile = true }
            }
        }
        .frame(height: Size.control)
        .onChange(of: state.invitedCode) { _, code in
            if code != nil, session?.isPaired == false { pairing = true }
        }
        .sheet(isPresented: Binding(get: { state.showsProfile }, set: { state.showsProfile = $0 })) {
            // A plain slide-up: a zoom out of the round avatars would morph through the sheet's rectangle.
            ProfileHub(state: state, erase: erase)
        }
        .sheet(isPresented: $checkingIn) {
            MoodPicker(state: state)
        }
        .sheet(isPresented: $pairing, onDismiss: { state.invitedCode = nil }) {
            if let session {
                PairingSheet(model: session.pairing, prefill: state.invitedCode ?? "") { session.pairingFinished() }
            }
        }
    }
}
