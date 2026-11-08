import SwiftUI

/// The one error style: an icon and a short line in `Ink.destructive`. Put it under a field that wears `.errorField()`.
public struct ErrorLine: View {
  let text: String

  public init(_ text: String) { self.text = text }

  public var body: some View {
    Label {
      Text(text).font(.nookiCallout)
    } icon: {
      Image(systemName: "exclamationmark.circle.fill")
    }
    .foregroundStyle(Ink.destructive)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

extension View {
  /// The error state of a field: a tinted fill and a border in `Ink.destructive`.
  public func errorField(_ failed: Bool) -> some View {
    background(
      failed ? Ink.destructive.opacity(0.12) : .clear, in: .rect(cornerRadius: Radius.card)
    )
    .overlay {
      RoundedRectangle(cornerRadius: Radius.card)
        .strokeBorder(failed ? Ink.destructive : .clear, lineWidth: 1.5)
    }
  }
}

/// A quiet action: honey words, no capsule.
public struct QuietButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.nookiHeadline)
      .foregroundStyle(Ink.accentText)
      .frame(maxWidth: .infinity, minHeight: Size.control)
      .contentShape(.rect)
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}
