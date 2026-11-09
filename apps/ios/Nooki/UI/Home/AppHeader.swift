import SwiftUI
import Design

/// Nothing sits in it but what a tab hangs under it (the World's room switch), which shares its glass container.
struct AppHeader<Below: View>: View {
    let state: HomeState
    var erase: () -> Void
    @ViewBuilder var below: Below
    @State private var pairing = false
    @State private var checkingIn = false
    @AppStorage(PlusPass.key) private var plus = false
    @Environment(ServerSession.self) private var session: ServerSession?

    var body: some View {
        // One container for all the glass of the top bar, as the tab bar has, so it is sampled together.
        GlassGroup {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: GlassMetrics.gap) {
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
                .frame(height: Size.control)
                below
            }
            .animation(.easeInOut(duration: 0.2), value: state.tab)
        }
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
