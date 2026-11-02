import AuthenticationServices
import DesignSystem
import SwiftUI

/// The welcome screen and Sign in with Apple. Calls `onSignedIn` once a session is saved.
public struct OnboardingView: View {
  private let model: SignInModel
  private let onSignedIn: () -> Void

  public init(model: SignInModel, onSignedIn: @escaping () -> Void) {
    self.model = model
    self.onSignedIn = onSignedIn
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      VStack(spacing: Spacing.large) {
        Spacer(minLength: 0)
        VStack(spacing: Spacing.small) {
          Text("A little house for two")
            .billetType(.title)
            .foregroundStyle(Palette.paper.color)
            .accessibilityAddTraits(.isHeader)
          Text("Draw a note and the cat carries it to your partner's wall.")
            .billetType(.body)
            .foregroundStyle(Palette.muted.color)
        }
        .multilineTextAlignment(.center)
        status
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.medium)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        action
          .padding(.horizontal, Spacing.medium)
          .padding(.vertical, Spacing.small)
      }
    }
    .calmAnimation(value: model.state)
    .task { model.appeared() }
    .onChange(of: model.state) { _, state in
      if state == .signedIn { onSignedIn() }
    }
  }

  @ViewBuilder private var status: some View {
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
    case .ready, .signedIn:
      EmptyView()
    }
  }

  @ViewBuilder private var action: some View {
    switch model.state {
    case .ready(let nonce, _):
      SignInWithAppleButton(
        .continue,
        onRequest: { request in
          request.requestedScopes = []
          request.nonce = nonce
        },
        onCompletion: { result in Self.handle(result, on: model) }
      )
      .signInWithAppleButtonStyle(.white)
      .frame(height: Target.row)
      .accessibilityIdentifier("signInWithApple")
    case .failed:
      BilletButton("Try again", rank: .primary) { model.retry() }
    case .idle, .fetchingNonce, .exchanging, .signedIn:
      EmptyView()
    }
  }

  /// Tells the model what Apple's sheet ended with.
  static func handle(_ result: Result<ASAuthorization, any Error>, on model: SignInModel) {
    switch Self.outcome(of: result) {
    case .token(let token): model.appleCompleted(identityToken: token)
    case .cancelled: model.appleCancelled()
    case .failed: model.appleFailed()
    }
  }

  enum Outcome: Equatable {
    case token(String)
    case cancelled
    case failed
  }

  static func outcome(of result: Result<ASAuthorization, any Error>) -> Outcome {
    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let data = credential.identityToken, let token = String(data: data, encoding: .utf8)
      else { return .failed }
      return .token(token)
    case .failure(let error):
      if (error as? ASAuthorizationError)?.code == .canceled { return .cancelled }
      return .failed
    }
  }
}

extension SignInFailure {
  /// What the screen tells the user.
  var message: String {
    switch self {
    case .appleRefused: "Apple couldn't sign you in. Try again."
    case .rejected: "Billet didn't accept that sign-in. Try again."
    case .unavailable: "Billet can't be reached right now. Try again in a moment."
    case .storage: "Billet couldn't save your sign-in on this phone. Try again."
    }
  }
}
