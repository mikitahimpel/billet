import AuthenticationServices
import Design
import SwiftUI

/// The calm card under Settings' Account row: Sign in with Apple to save the account for a new phone, in
/// each state of ``AppleLinkMachine``. Linking is optional; nothing else in the app asks for it.
public struct AppleAccountSection: View {
  private let model: AppleLinkModel
  @Environment(\.colorScheme) private var colorScheme

  public init(model: AppleLinkModel) { self.model = model }

  public var body: some View {
    GroupedSection(footer: footer) {
      content
    }
    .task { model.appeared() }
    .animation(Motion.fade(), value: model.state)
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    // The steps before the answer share one row, so nothing in the section moves until it is known.
    case .idle, .checking, .preparing:
      Row("Sign in with Apple", detail: "Checking…", symbol: "person.crop.circle.badge.checkmark") {
        ProgressView()
      }
    case .checkFailed:
      Row(
        "Sign in with Apple", detail: "Couldn't check your account", symbol: "wifi.exclamationmark"
      ) {
        RetryButton(compact: true) { model.retry() }.fixedSize()
      }
    case .ready(let nonce, _):
      VStack(alignment: .leading, spacing: Space.m) {
        Text("Link your Apple ID to save your account, with your cat and notes.")
          .font(.ourioCallout)
          .foregroundStyle(Ink.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        appleButton(nonce: nonce)
      }
      .padding(Space.l)
    case .linking:
      Row("Linking your Apple ID…", symbol: "person.crop.circle.badge.checkmark") { ProgressView() }
    case .linked:
      Row(
        "Signed in with Apple", detail: "Your cat and notes are saved to your Apple ID",
        symbol: "checkmark.seal.fill", tint: .sage
      ) {}
      .accessibilityIdentifier("appleLinked")
    case .failed(let failure, _):
      VStack(alignment: .leading, spacing: Space.m) {
        ErrorLine(failure.linkMessage)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("appleLinkError")
        RetryButton(failure == .appleIdInUse ? "Choose another Apple ID" : "Try again") {
          model.retry()
        }
      }
      .padding(Space.l)
    }
  }

  private var footer: String? {
    switch model.state {
    case .linked:
      "Ourio keeps only Apple's private ID for you, never your name or email. Deleting your account also ends this link."
    case .ready, .failed:
      "Optional. Ourio keeps only Apple's private ID for you, never your name or email."
    case .idle, .checking, .checkFailed, .preparing, .linking:
      nil
    }
  }

  private func appleButton(nonce: String) -> some View {
    SignInWithAppleButton(
      .signIn,
      onRequest: { request in
        request.requestedScopes = []
        request.nonce = nonce
      },
      onCompletion: { result in Self.handle(result, on: model) }
    )
    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    .frame(height: Size.button)
    .corners(.control)
    .accessibilityIdentifier("signInWithApple")
  }

  static func handle(_ result: Result<ASAuthorization, any Error>, on model: AppleLinkModel) {
    switch AppleSheetOutcome.identityToken(of: result) {
    case .token(let token): model.appleCompleted(identityToken: token)
    case .cancelled: model.appleCancelled()
    case .failed, .code: model.appleFailed()
    }
  }
}
