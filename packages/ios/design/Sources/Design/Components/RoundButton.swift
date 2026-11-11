import SwiftUI

/// A round control on content: add to a list, the next picture, a small action beside a row. Opaque;
/// over the room or a canvas the control is `GlassIconButton` instead.
public struct RoundButton: View {
  public enum Style: Hashable, Sendable {
    case quiet
    /// The screen's one accented control.
    case honey
  }

  let symbol: String
  let label: String
  let style: Style
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  public init(
    symbol: String, label: String, style: Style = .quiet, action: @escaping () -> Void
  ) {
    self.symbol = symbol
    self.label = label
    self.style = style
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.ourioHeadline)
        .foregroundStyle(glyph)
        .frame(width: Size.control, height: Size.control)
        .background { Circle().fill(fill) }
        .contentShape(.circle)
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityLabel(label)
  }

  private var glyph: Color {
    guard isEnabled else { return Ink.disabledText }
    switch style {
    case .quiet: return Ink.text
    case .honey: return Ink.heroInk
    }
  }

  private var fill: AnyShapeStyle {
    guard isEnabled else { return AnyShapeStyle(Ink.disabledFill) }
    switch style {
    case .quiet: return AnyShapeStyle(Ink.surfaceRaised)
    case .honey: return Ink.accentFace
    }
  }
}

#Preview("Round button") {
  BothSchemes {
    Card {
      HStack(spacing: Space.m) {
        RoundButton(symbol: "plus", label: "Add", style: .honey) {}
        RoundButton(symbol: "arrow.uturn.backward", label: "Undo") {}
        RoundButton(symbol: "checkmark", label: "Added") {}.disabled(true)
      }
    }
    .padding(Space.gutter)
  }
}
