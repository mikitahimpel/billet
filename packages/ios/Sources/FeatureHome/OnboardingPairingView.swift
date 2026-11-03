import DesignSystem
import Pet
import PetScene
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// What the pairing in the first-launch scene asks of whoever runs it: the demo room, or the
/// scripted pair of a replay.
struct OnboardingPairingActions {
  var create: () -> Void
  /// Joins with a code as typed; the runner checks it.
  var join: (String) -> Void
  var cancel: () -> Void
  /// Leaves for the app while the partner has not joined yet, where that is allowed.
  var goIn: (() -> Void)?
  /// Shown on the welcome when set.
  var tryAlone: (() -> Void)?
}

/// Pairing inside the first-launch scene: the heart opens into two halves, this phone's stays,
/// and the other waits with the code on a tag, or flies in once the partner's code is entered.
/// "Invite your person" shares the code. The halves join with a burst of light and haptics.
struct OnboardingPairingView: View {
  let scenes: [any PetScene]
  let lighting: RoomLighting
  let memory: OnboardingMemory?
  let pairing: OnboardingPairing
  let failure: String?
  let actions: OnboardingPairingActions
  let send: (OnboardingPairing.Event) -> Void

  @State private var typed = ""
  @State private var copies = 0

  /// How long the joined heart holds before the app goes on.
  static let joinedHold = Duration.milliseconds(1_900)
  /// The longest the joined moment waits for the halves to meet, as when no scene shows them.
  static let joinedLimit = Duration.seconds(4)

  private var typedCode: String {
    typed.filter { !$0.isWhitespace }.uppercased()
  }

  var body: some View {
    CinematicOnboardingView(
      scenes: scenes, lighting: lighting, memory: memory, heading: heading, rest: pairing.scene,
      onEvent: handle, back: back
    ) {
      if let failure {
        Text(failure)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
          .multilineTextAlignment(.center)
          .padding(Spacing.medium)
          .frame(maxWidth: .infinity)
          .card()
          .transition(.opacity)
          .accessibilityIdentifier("pairingError")
      }
      buttons
    }
    .sensoryFeedback(.selection, trigger: copies)
    .task(id: pairing.step) {
      guard case .joined = pairing.step else { return }
      try? await Task.sleep(for: Self.joinedLimit)
      guard !Task.isCancelled else { return }
      send(.joinShown)
    }
  }

  private var heading: OnboardingHeading {
    switch pairing.step {
    case .welcome, .done:
      .welcome
    case .inviting:
      OnboardingHeading(
        title: "Half of it is yours",
        detail: "The other half waits for your person. Send them the code on the tag.")
    case .enteringCode:
      OnboardingHeading(
        title: "Enter your person's code",
        detail: "Their half of the heart comes to you.")
    case .joining:
      OnboardingHeading(title: "Their half is on its way", detail: "Joining your person…")
    case .joined:
      OnboardingHeading(title: "Two halves, one house", detail: "You're a pair.")
    }
  }

  @ViewBuilder private var buttons: some View {
    switch pairing.step {
    case .welcome:
      GlassGroup {
        VStack(spacing: Spacing.small) {
          BilletButton("Invite your person", rank: .primary, systemImage: "heart") {
            actions.create()
          }
          BilletButton("I have a code", rank: .secondary) { send(.enterCode) }
          if let tryAlone = actions.tryAlone {
            BilletButton("Try alone with a fake partner", rank: .secondary, action: tryAlone)
          }
        }
      }
    case .inviting(let code, let live):
      GlassGroup {
        VStack(spacing: Spacing.small) {
          ShareLink(item: Self.invitation(code: code)) {
            ButtonLabel("Invite your person", rank: .primary, systemImage: "square.and.arrow.up")
          }
          .billetButton(.primary)
          .accessibilityHint("Our code is \(code.map(String.init).joined(separator: " "))")
          .accessibilityIdentifier("inviteYourPerson")
          if !live {
            LoadingLine("Setting up your pair…")
          } else if let goIn = actions.goIn {
            BilletButton("Go in, they can join later", rank: .secondary, action: goIn)
          }
        }
      }
    case .enteringCode:
      codeField
      BilletButton("Join", rank: .primary) { actions.join(typedCode) }
        .disabled(typedCode.isEmpty)
    case .joining:
      EmptyView()
    case .joined, .done:
      EmptyView()
    }
  }

  /// The top-left back button of each step after the welcome: from the invite or the joining it
  /// cancels, from the code it goes back to the welcome.
  private var back: (() -> Void)? {
    switch pairing.step {
    case .inviting, .joining: actions.cancel
    case .enteringCode: { send(.back) }
    case .welcome, .joined, .done: nil
    }
  }

  private var codeField: some View {
    TextField("Their code", text: $typed)
      // The app's own face, with figures of one width so the code does not shift as it is typed.
      .billetType(.heading)
      .monospacedDigit()
      .foregroundStyle(Palette.gold.color)
      .multilineTextAlignment(.center)
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.characters)
      #endif
      .padding(.horizontal, Spacing.medium)
      .frame(maxWidth: .infinity, minHeight: Target.row)
      .card()
      // Ten letters in one line: larger than this they run off a small phone.
      .dynamicTypeSize(...DynamicTypeSize.accessibility1)
      .accessibilityIdentifier("partnerCode")
  }

  /// What the share sheet sends.
  static func invitation(code: String) -> String {
    "Come share a little house with me on billet. Our code: \(code)"
  }

  private func handle(_ event: OnboardingSceneEvent) {
    switch event {
    case .joined:
      Task {
        try? await Task.sleep(for: Self.joinedHold)
        send(.joinShown)
      }
    case .codeTapped:
      if case .inviting(let code, _) = pairing.step {
        #if os(iOS)
          UIPasteboard.general.string = code
        #endif
        copies += 1
      }
    case .arrived, .heartTapped:
      break
    }
  }
}
