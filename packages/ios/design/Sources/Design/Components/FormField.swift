import SwiftUI

/// A labelled input: the label over it, and under it either the error or a footnote, never both.
public struct FormField<Input: View>: View {
  let label: String
  let footer: String?
  let error: String?
  let input: Input

  public init(
    _ label: String, footer: String? = nil, error: String? = nil,
    @ViewBuilder input: () -> Input
  ) {
    self.label = label
    self.footer = footer
    self.error = error
    self.input = input()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      Text(label)
        .font(.ourioCaption.weight(.semibold))
        .foregroundStyle(Ink.textSecondary)
        .padding(.horizontal, Space.l)
      input
      if let error {
        ErrorLine(error).padding(.horizontal, Space.l)
      } else if let footer {
        Text(footer)
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
          .padding(.horizontal, Space.l)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

extension FormField where Input == Field {
  public init(
    _ label: String, placeholder: String, text: Binding<String>, axis: Axis = .horizontal,
    lines: ClosedRange<Int> = 1...1, footer: String? = nil, error: String? = nil
  ) {
    self.init(label, footer: footer, error: error) {
      Field(placeholder, text: text, axis: axis, lines: lines, failed: error != nil)
    }
  }
}

#Preview("Form field") {
  BothSchemes {
    VStack(spacing: Space.section) {
      FormField(
        "Name", placeholder: "Your name", text: .constant("Mikita"),
        footer: "Your partner sees it.")
      FormField(
        "Invite code", placeholder: "Code", text: .constant("K7QM"),
        error: "That code isn't working.")
    }
    .padding(Space.gutter)
  }
}
