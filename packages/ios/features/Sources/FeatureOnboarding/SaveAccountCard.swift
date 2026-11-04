import DesignSystem
import SwiftUI

/// "Save your cat and notes": links the anonymous account to Sign in with Apple, so a phone without
/// this iCloud account can find them too. A small card the user can close; it never stands in the
/// way. `model` must be a ``SignInModel`` made with `purpose: .link`.
public struct SaveAccountCard: View {
  private let model: SignInModel
  private let onLinked: () -> Void
  private let onClose: () -> Void

  public init(model: SignInModel, onLinked: @escaping () -> Void, onClose: @escaping () -> Void) {
    self.model = model
    self.onLinked = onLinked
    self.onClose = onClose
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack(alignment: .firstTextBaseline) {
        Text("Save your cat and notes")
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Spacer(minLength: Spacing.small)
        Button(action: onClose) {
          Image(systemName: "xmark")
            .foregroundStyle(Palette.paper.color)
            .frame(width: Target.row, height: Target.row)
        }
        .accessibilityLabel("Not now")
        .accessibilityIdentifier("saveAccountClose")
      }
      Text("Sign in with Apple, and a new phone finds them even without this iCloud account.")
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
      SignInControls(model: model, onSignedIn: onLinked)
    }
    .padding(Spacing.medium)
    .card()
    .accessibilityIdentifier("saveAccountCard")
  }
}
