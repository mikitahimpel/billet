#if canImport(UIKit)
  import Design
  import SwiftUI
  import Transport

  public struct PairToPlayButton: View {
    @Environment(\.usServer) private var session
    @State private var pairing = false

    public init() {}

    public var body: some View {
      if let session, !session.isPaired, session.hasFinishedSignIn {
        PrimaryButton("Pair with your partner", symbol: "heart.fill", fullWidth: false) {
          pairing = true
        }
        .padding(.top, Space.s)
        .sheet(isPresented: $pairing) {
          session.pairingSheet()
        }
      }
    }
  }
#endif
