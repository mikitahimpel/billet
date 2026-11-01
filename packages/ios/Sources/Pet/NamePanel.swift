import DesignSystem
import SwiftUI

/// Asks the pair to name the cat. Shown until either partner has chosen a name.
public struct NamePanel: View {
  private let onName: (String) -> Void

  @State private var typed = ""

  public init(onName: @escaping (String) -> Void) {
    self.onName = onName
  }

  private var name: String? { CatName.clean(typed) }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      Text("Name your cat")
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
      Text("Whoever chooses first names it for both of you.")
        .billetType(.label)
        .foregroundStyle(Palette.muted.color)
        .multilineTextAlignment(.center)
      TextField("Name", text: $typed)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit(submit)
        .padding(.horizontal, Spacing.medium)
        .frame(minHeight: Target.row)
        .card()
        .accessibilityIdentifier("catName")
      BilletButton("Name the cat", rank: .primary, action: submit)
        .disabled(name == nil)
    }
  }

  private func submit() {
    if let name { onName(name) }
  }
}
