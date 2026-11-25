import FeatureShop
import SwiftUI
import Design

/// Nothing sits in it but what a tab hangs under it (the World's room switch), which shares its glass container.
struct AppHeader<Below: View>: View {
    let state: HomeState
    var erase: () -> Void
    @ViewBuilder var below: Below
    @State private var pairing = false
    @State private var checkingIn = false
    @State private var pairedAlready = false
    @Environment(ServerSession.self) private var session: ServerSession?

    var body: some View {
        // One container for all the glass of the top bar, as the tab bar has, so it is sampled together.
        GlassGroup {
            VStack(spacing: Space.m) {
                HStack(alignment: .center, spacing: GlassMetrics.gap) {
                    InboxButton(unread: session?.inbox.unread ?? 0) { state.showsInbox = true }
                    MoodHeaderButton(state: state) { checkingIn = true }

                    Spacer(minLength: 0)

                    Button { state.shop.askForCoins() } label: { CoinPill(coins: state.shop.coins) }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("\(state.shop.coins) coins")
                        .accessibilityHint("Shows your coins, how to get more and where they went")
                        .accessibilityIdentifier("coins")

                    CoupleButton(state: state) { state.showsProfile = true }
                }
                .frame(height: Size.control)
                below
            }
            .animation(Motion.fade(0.2), value: state.tab)
        }
        // Outside the group, so the badges it draws above its glass are capped too.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Initial too: a link that launched the app arrives before the header is on screen.
        .onChange(of: state.invitedCode, initial: true) { _, code in
            guard code != nil, let session else { return }
            if session.isPaired { pairedAlready = true } else { pairing = true }
        }
        .alert("You already have a partner", isPresented: $pairedAlready) {
            Button("OK", role: .cancel) { state.invitedCode = nil }
        } message: {
            Text("This iPhone is paired, so the invite link has nothing to join.").font(.ourioCallout)
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
                PairingSheet(model: session.pairing, server: session.baseURL, prefill: state.invitedCode ?? "") { session.pairingFinished() }
            }
        }
    }
}
