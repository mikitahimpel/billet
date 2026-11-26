#if canImport(UIKit)
  import Design
  import SwiftUI
  import Transport

  public struct PairToPlayButton: View {
    @Environment(\.usServer) private var session
    @State private var pairing = false

    private let fullWidth: Bool

    /// Full width as a card's own action; at its own size under an empty state.
    public init(fullWidth: Bool = false) {
      self.fullWidth = fullWidth
    }

    public var body: some View {
      if let session, !session.isPaired, session.hasFinishedSignIn {
        PrimaryButton("Pair with your partner", symbol: "heart.fill", fullWidth: fullWidth) {
          pairing = true
        }
        .padding(.top, fullWidth ? 0 : Space.s)
        .sheet(isPresented: $pairing) {
          session.pairingSheet()
        }
      }
    }
  }
#endif
