import DesignSystem
import SwiftUI

/// The sheet asking the pair to name the cat. Shown until either partner has chosen a name.
public struct NamePanel: View {
  private let onName: (String) -> Void

  @State private var typed = ""
  @FocusState private var isTyping: Bool

  public init(onName: @escaping (String) -> Void) {
    self.onName = onName
  }

  private var name: String? { CatName.clean(typed) }

  public var body: some View {
    SheetPanel("Name your cat") {
      Text("Whoever chooses first names it for both of you.")
        .billetType(.label)
        .foregroundStyle(Palette.muted.color)
      TextField("Name", text: $typed)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .autocorrectionDisabled()
        .focused($isTyping)
        .submitLabel(.done)
        .onSubmit(submit)
        .padding(.horizontal, Spacing.medium)
        .frame(minHeight: Target.row)
        .card()
        .accessibilityIdentifier("catName")
      BilletButton("Name the cat", rank: .primary, action: submit)
        .disabled(name == nil)
    }
    .onAppear { isTyping = true }
  }

  private func submit() {
    if let name { onName(name) }
  }
}
