import Design
import SwiftUI

struct PairToPlayButton: View {
    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var pairing = false

    var body: some View {
        if let session, !session.isPaired, session.signIn.state == .signedIn {
            PrimaryButton("Pair with your partner", symbol: "heart.fill", fullWidth: false) { pairing = true }
                .padding(.top, Space.s)
                .sheet(isPresented: $pairing) {
                    PairingSheet(model: session.pairing) { session.pairingFinished() }
                }
        }
    }
}
