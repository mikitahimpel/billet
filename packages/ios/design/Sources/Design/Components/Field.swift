import SwiftUI

/// The app's one text field: a raised fill in the shape of the buttons, so a field and the button under it read
/// as one family. One line is a capsule; a vertical field grows and keeps the round ends. `.focused`, `.onSubmit`,
/// `.submitLabel` and the input traits go on the `Field` itself.
public struct Field: View {
  let placeholder: String
  @Binding var text: String
  let axis: Axis
  let lines: ClosedRange<Int>
  let font: Font
  let failed: Bool

  public init(
    _ placeholder: String, text: Binding<String>, axis: Axis = .horizontal,
    lines: ClosedRange<Int> = 1...1, font: Font = .ourioBody, failed: Bool = false
  ) {
    self.placeholder = placeholder
    _text = text
    self.axis = axis
    self.lines = lines
    self.font = font
    self.failed = failed
  }

  public var body: some View {
    TextField(
      placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Ink.textTertiary),
      axis: axis
    )
    .lineLimit(lines)
    .font(font)
    .foregroundStyle(Ink.text)
    .fieldSurface(failed: failed)
  }
}

extension View {
  /// The surface of a `Field`, for an input the package can't build itself (a code entry, a search bar with a
  /// leading icon). `failed` draws the error state; put an `ErrorLine` under it.
  public func fieldSurface(failed: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    return
      self
      .tint(Ink.accentText)
      .padding(.horizontal, Space.gutter)
      .padding(.vertical, Space.m)
      .frame(maxWidth: .infinity, minHeight: Size.button, alignment: .leading)
      .background {
        shape.fill(Ink.surfaceRaised)
        if failed { shape.fill(Ink.destructive.opacity(0.12)) }
      }
      .overlay {
        shape.strokeBorder(
          failed ? Ink.destructive : Ink.separator, lineWidth: failed ? 1.5 : 0.5)
      }
      .containerShape(shape)
      .contentShape(shape)
  }
}

#Preview("Field") {
  BothSchemes {
    VStack(spacing: Space.m) {
      Field("A few words (optional)", text: .constant(""), axis: .vertical, lines: 1...3)
      Field("Name", text: .constant("Mikita"))
      Field("Code", text: .constant("K7QM"), failed: true)
      ErrorLine("That code isn't working.")
      PrimaryButton("Pair") {}
      Card {
        VStack(spacing: Space.m) {
          Field("Code", text: .constant(""))
            .multilineTextAlignment(.center)
          SecondaryButton("Pair") {}
        }
      }
    }
    .padding(Space.gutter)
  }
}
