import Delivery
import DesignSystem
import SwiftUI

/// First launch: a welcome, then create a pair or enter the partner's code.
struct PairingView: View {
  private enum Step {
    case welcome
    case enterCode
  }

  let model: AppModel

  @State private var step = Step.welcome
  @State private var partnerCode = ""

  private var typedCode: String {
    partnerCode.filter { !$0.isWhitespace }.uppercased()
  }

  var body: some View {
    ZStack {
      EveningBackground()
      ScrollView {
        VStack(spacing: Spacing.large) {
          ScenePanel {
            SceneCanvas(HouseArt.art(for: .lit))
          }
          .lampGlow()
          .accessibilityHidden(true)
          message
          failureMessage
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        GlassGroup {
          VStack(spacing: Spacing.small) { actions }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
      }
    }
    .calmAnimation(value: step)
    .calmAnimation(value: model.failure)
  }

  /// The state of the flow, as the screen shows it.
  private enum Screen {
    case welcome
    case enterCode
    case creating(PairSession)
    case joining
  }

  private var screen: Screen {
    switch model.stage {
    case .pairing(let session, creating: true): .creating(session)
    case .pairing(_, creating: false): .joining
    case .unpaired, .paired: step == .welcome ? .welcome : .enterCode
    }
  }

  @ViewBuilder private var message: some View {
    switch screen {
    case .welcome:
      heading(
        "A little house for two",
        detail: "Draw a note and the cat carries it to your partner's wall.")
    case .enterCode:
      heading("Enter your partner's code", detail: "They'll find it on their phone.")
      codeField
    case .creating(let session):
      heading(
        "Your pair code",
        detail: "Send this to your partner. They choose Enter code and type it in.")
      PairCodeCard(code: session.room.code)
      if !session.hasConnected {
        LoadingLine("Setting up your pair…")
      }
    case .joining:
      LoadingLine("Joining your partner…")
    }
  }

  @ViewBuilder private var actions: some View {
    switch screen {
    case .welcome:
      BilletButton("Create pair", rank: .primary) { model.createPair() }
      BilletButton("Enter code", rank: .secondary) { step = .enterCode }
    case .enterCode:
      BilletButton("Join", rank: .primary) { model.join(code: typedCode) }
        .disabled(typedCode.isEmpty)
      BilletButton("Back", rank: .secondary) { step = .welcome }
    case .creating(let session):
      if session.hasConnected {
        BilletButton("Continue", rank: .primary) { model.finishCreating() }
      }
      BilletButton("Cancel", rank: .secondary) { model.cancelPairing() }
    case .joining:
      BilletButton("Cancel", rank: .secondary) { model.cancelPairing() }
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

  private var codeField: some View {
    TextField("Partner's code", text: $partnerCode)
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
  }

  @ViewBuilder private var failureMessage: some View {
    if let failure = model.failure {
      Text(failure.message)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity)
        .card()
        .transition(.opacity)
        .accessibilityIdentifier("pairingError")
    }
  }
}
