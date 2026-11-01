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
          .frame(maxWidth: 260)
          .lampGlow()
          .accessibilityHidden(true)
          content
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .animation(Motion.gentle, value: step)
  }

  @ViewBuilder private var content: some View {
    switch model.stage {
    case .pairing(let session, creating: true):
      creating(session)
    case .pairing(_, creating: false):
      joining
    case .unpaired, .paired:
      switch step {
      case .welcome: welcome
      case .enterCode: enterCode
      }
    }
  }

  private var welcome: some View {
    VStack(spacing: Spacing.large) {
      VStack(spacing: Spacing.small) {
        Text("A little house for two")
          .billetType(.title)
          .foregroundStyle(Palette.paper.color)
          .accessibilityAddTraits(.isHeader)
        Text("Draw a note and the cat carries it to your partner's wall.")
          .billetType(.body)
          .foregroundStyle(Palette.paperTurned.color)
      }
      .multilineTextAlignment(.center)
      failureMessage
      Button("Create pair") { model.createPair() }
        .buttonStyle(PrimaryButtonStyle())
      Button("Enter code") { step = .enterCode }
        .buttonStyle(SecondaryButtonStyle())
    }
  }

  private func creating(_ session: PairSession) -> some View {
    VStack(spacing: Spacing.large) {
      VStack(spacing: Spacing.small) {
        Text("Your pair code")
          .billetType(.title)
          .foregroundStyle(Palette.paper.color)
          .accessibilityAddTraits(.isHeader)
        Text("Send this to your partner. They choose Enter code and type it in.")
          .billetType(.body)
          .foregroundStyle(Palette.paperTurned.color)
      }
      .multilineTextAlignment(.center)
      PairCodeCard(code: session.room.code)
      if session.hasConnected {
        Button("Continue") { model.finishCreating() }
          .buttonStyle(PrimaryButtonStyle())
      } else {
        LoadingLine("Setting up your pair…")
      }
      Button("Cancel") { model.cancelPairing() }
        .buttonStyle(SecondaryButtonStyle())
    }
  }

  private var joining: some View {
    VStack(spacing: Spacing.large) {
      LoadingLine("Joining your partner…")
      Button("Cancel") { model.cancelPairing() }
        .buttonStyle(SecondaryButtonStyle())
    }
  }

  private var enterCode: some View {
    VStack(spacing: Spacing.large) {
      Text("Enter your partner's code")
        .billetType(.title)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      codeField
      failureMessage
      Button("Join") { model.join(code: typedCode) }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(typedCode.isEmpty)
        .opacity(typedCode.isEmpty ? 0.5 : 1)
      Button("Back") { step = .welcome }
        .buttonStyle(SecondaryButtonStyle())
    }
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
      .padding(Spacing.small)
      .frame(minHeight: Target.primary)
      .background(Palette.plate.color, in: .rect(cornerRadius: Radius.plate))
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
        .litPanel(cornerRadius: Radius.control)
        .accessibilityIdentifier("pairingError")
    }
  }
}
