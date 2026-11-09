import SwiftUI

/// The one error style: an icon and a short line in `Ink.destructive`. Put it under a `Field(failed: true)`.
public struct ErrorLine: View {
  let text: String

  public init(_ text: String) { self.text = text }

  public var body: some View {
    Label {
      Text(text).font(.ourioCallout)
    } icon: {
      Image(systemName: "exclamationmark.circle.fill")
    }
    .foregroundStyle(Ink.destructive)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// A quiet action: honey words, no capsule.
public struct QuietButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.ourioHeadline)
      .foregroundStyle(Ink.accentText)
      .frame(maxWidth: .infinity, minHeight: Size.control)
      .contentShape(.rect)
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}
