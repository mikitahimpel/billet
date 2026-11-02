import DesignSystem
import SwiftUI

/// The pairing screens: choose, show an invite and wait, or enter the partner's code. Calls
/// `onPaired` once the account has a partner.
public struct PairingFlowView: View {
  /// How often a shown invite is checked for a claim.
  static let checkEvery = Duration.seconds(3)

  private let model: PairingModel
  private let onPaired: () -> Void
  @State private var typedCode = ""
  @State private var entering = false

  public init(model: PairingModel, onPaired: @escaping () -> Void) {
    self.model = model
    self.onPaired = onPaired
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      ScrollView {
        VStack(spacing: Spacing.large) {
          content
          failure
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.large)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        GlassGroup { VStack(spacing: Spacing.small) { actions } }
          .padding(.horizontal, Spacing.medium)
          .padding(.vertical, Spacing.small)
      }
    }
    .calmAnimation(value: model.state)
    .task(id: isWaiting) {
      guard isWaiting else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.checkEvery)
        guard !Task.isCancelled else { return }
        model.tick()
      }
    }
    .onChange(of: model.state) { _, state in
      if case .paired = state { onPaired() }
    }
  }

  private var isWaiting: Bool {
    if case .waiting = model.state { true } else { false }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .choosing where entering:
      heading("Enter your partner's code", detail: "They'll find it on their phone.")
      TextField("Partner's code", text: $typedCode)
        .billetType(.numeral)
        .foregroundStyle(Palette.gold.color)
        .multilineTextAlignment(.center)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.characters)
        #endif
        .padding(.horizontal, Spacing.medium)
        .frame(minHeight: Target.row)
        .card()
        .accessibilityIdentifier("partnerCode")
    case .choosing:
      heading(
        "A little house for two",
        detail: "Make a code for your partner, or enter the one they sent you.")
    case .creating:
      LoadingLine("Making your code…")
    case .waiting(let code, _, _):
      heading(
        "Your pair code",
        detail: "Send this to your partner. This screen moves on when they've entered it.")
      PairCodeCard(code: code)
      LoadingLine("Waiting for your partner…")
    case .claiming:
      LoadingLine("Joining your partner…")
    case .paired:
      LoadingLine("Paired.")
    }
  }

  @ViewBuilder private var actions: some View {
    switch model.state {
    case .choosing where entering:
      BilletButton("Join", rank: .primary) { model.submit(code: typedCode) }
        .disabled(typedCode.allSatisfy(\.isWhitespace))
      BilletButton("Back", rank: .secondary) { entering = false }
    case .choosing:
      BilletButton("Create code", rank: .primary) { model.createInvite() }
      BilletButton("Enter code", rank: .secondary) { entering = true }
    case .waiting, .creating, .claiming:
      BilletButton("Cancel", rank: .secondary) { model.cancel() }
    case .paired:
      EmptyView()
    }
  }

  @ViewBuilder private var failure: some View {
    if case .choosing(let failure?, _) = model.state {
      Text(Self.message(for: failure))
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityIdentifier("pairingError")
    }
  }

  static func message(for failure: PairingFailure) -> String {
    switch failure {
    case .invalidCode:
      "That code isn't working. It may be mistyped, expired, already used or your own."
    case .alreadyPaired:
      "You already have a partner. Unpair in Settings before pairing again."
    case .signedOut:
      "You've been signed out. Open the app again to sign in."
    case .unavailable:
      "Billet can't be reached right now. Try again in a moment."
    }
  }

  private func heading(_ title: String, detail: String) -> some View {
    VStack(spacing: Spacing.small) {
      Text(title)
        .billetType(.title)
        .foregroundStyle(Palette.paper.color)
        .accessibilityAddTraits(.isHeader)
      Text(detail)
        .billetType(.body)
        .foregroundStyle(Palette.muted.color)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }
}
