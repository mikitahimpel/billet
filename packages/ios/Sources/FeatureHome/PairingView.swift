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
      Palette.page.color.ignoresSafeArea()
      ScrollView {
        VStack(spacing: Spacing.large) {
          SceneCanvas(TinyHouseArt.art)
            .frame(width: 120)
            .accessibilityHidden(true)
          content
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .animation(.easeInOut(duration: 0.2), value: step)
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
          .foregroundStyle(Palette.muted.color)
      }
      .multilineTextAlignment(.center)
      failureMessage
      Button("Create pair") { model.createPair() }
        .buttonStyle(PrimaryButtonStyle())
      SecondaryButton("Enter code") { step = .enterCode }
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
          .foregroundStyle(Palette.muted.color)
      }
      .multilineTextAlignment(.center)
      PairCodeCard(code: session.room.code)
      if session.hasConnected {
        Button("Continue") { model.finishCreating() }
          .buttonStyle(PrimaryButtonStyle())
      } else {
        LoadingLine("Setting up your pair…")
      }
      SecondaryButton("Cancel") { model.cancelPairing() }
    }
  }

  private var joining: some View {
    VStack(spacing: Spacing.large) {
      LoadingLine("Joining your partner…")
      SecondaryButton("Cancel") { model.cancelPairing() }
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
      SecondaryButton("Back") { step = .welcome }
    }
  }

  private var codeField: some View {
    TextField("Partner's code", text: $partnerCode)
      .font(.custom(BilletFonts.monoFamily, size: 21, relativeTo: .title3))
      .foregroundStyle(Palette.paper.color)
      .multilineTextAlignment(.center)
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.characters)
      #endif
      .padding(Spacing.small)
      .frame(minHeight: Target.minimum)
      .background(Palette.raised.color, in: .rect(cornerRadius: Radius.control))
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
        .background(Palette.raised.color, in: .rect(cornerRadius: Radius.control))
        .accessibilityIdentifier("pairingError")
    }
  }
}

/// A spinner and what it is waiting for.
private struct LoadingLine: View {
  private let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    HStack(spacing: Spacing.small) {
      ProgressView().tint(Palette.paper.color)
      Text(text)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
    }
    .frame(minHeight: Target.minimum)
    .accessibilityElement(children: .combine)
  }
}

/// The quieter action beside a primary one.
private struct SecondaryButton: View {
  private let title: String
  private let action: () -> Void

  init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .frame(maxWidth: .infinity, minHeight: Target.minimum)
        .background(Palette.raised.color, in: .rect(cornerRadius: Radius.control))
        .contentShape(.rect(cornerRadius: Radius.control))
    }
    .buttonStyle(.plain)
  }
}
