import SwiftUI

extension View {
  /// A glyph or label drawn at `size` points at the default text size that grows and shrinks with
  /// Dynamic Type as `style` does. For marks the text styles don't fit, such as a tab icon or a
  /// glyph in a round tile; text in a fixed frame caps it with `.dynamicTypeSize(...)`.
  public func ourioScaledFont(
    size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
    relativeTo style: Font.TextStyle = .body
  ) -> some View {
    modifier(ScaledFont(size: size, weight: weight, design: design, style: style))
  }
}

private struct ScaledFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  let weight: Font.Weight
  let design: Font.Design

  init(size: CGFloat, weight: Font.Weight, design: Font.Design, style: Font.TextStyle) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    self.weight = weight
    self.design = design
  }

  func body(content: Content) -> some View {
    content.font(.system(size: size, weight: weight, design: design))
  }
}

#Preview("Scaled font") {
  VStack(spacing: 16) {
    ForEach([DynamicTypeSize.small, .large, .xxxLarge, .accessibility2], id: \.self) { size in
      HStack(spacing: 12) {
        Image(systemName: "house.fill").ourioScaledFont(size: 18, weight: .semibold)
        Text("Home").ourioScaledFont(size: 11, weight: .medium, relativeTo: .caption2)
      }
      .dynamicTypeSize(size)
    }
  }
  .padding()
}
