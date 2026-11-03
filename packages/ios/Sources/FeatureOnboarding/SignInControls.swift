import AuthenticationServices
import DesignSystem
import SwiftUI

/// Sign in with Apple as one block for a screen of its own: a line while it gets ready or signs
/// in, the failure with Try again, and the button once it is ready. The same model and the same
/// handling as ``OnboardingView``. Calls `onSignedIn` once a session is saved.
public struct SignInControls: View {
  private let model: SignInModel
  private let onSignedIn: () -> Void

  public init(model: SignInModel, onSignedIn: @escaping () -> Void) {
    self.model = model
    self.onSignedIn = onSignedIn
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      switch model.state {
      case .idle, .fetchingNonce:
        LoadingLine("Getting ready…")
      case .exchanging:
        LoadingLine("Signing you in…")
      case .failed(let failure, _):
        Text(failure.message)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
          .multilineTextAlignment(.center)
          .padding(Spacing.medium)
          .frame(maxWidth: .infinity)
          .card()
          .accessibilityIdentifier("signInError")
        BilletButton("Try again", rank: .primary) { model.retry() }
      case .ready(let nonce, _):
        SignInWithAppleButton(
          .continue,
          onRequest: { request in
            request.requestedScopes = []
            request.nonce = nonce
          },
          onCompletion: { result in OnboardingView.handle(result, on: model) }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: Target.row)
        .accessibilityIdentifier("signInWithApple")
      case .signedIn:
        EmptyView()
      }
    }
    .calmAnimation(value: model.state)
    .task { model.appeared() }
    .onChange(of: model.state) { _, state in
      if state == .signedIn { onSignedIn() }
    }
  }
}
