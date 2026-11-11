import SwiftUI

extension View {
  /// A recess in a card: an art slot, a thumbnail's backdrop, an inset note. One flat opaque tone
  /// with a hairline of shade on its upper edge, where a card has light, and no shadow. Also the
  /// container shape; a picture that reaches its edge takes `.corners(_:)` of the same corner.
  public func wellSurface(_ corner: Corner = .inner) -> some View {
    modifier(WellSurface(corner: corner))
  }
}

private struct WellSurface: ViewModifier {
  let corner: Corner

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: corner.radius, style: .continuous)
  }

  func body(content: Content) -> some View {
    content
      .background(Ink.well, in: shape)
      .overlay {
        shape
          .strokeBorder(
            LinearGradient(
              colors: [Ink.wellShade, Ink.wellShade.opacity(0)], startPoint: .top,
              endPoint: .center),
            lineWidth: 1
          )
          .allowsHitTesting(false)
      }
      .containerShape(shape)
  }
}

/// The line between two rows on one card. `inset` is where it starts, so it can begin under a
/// row's title instead of under its icon.
public struct Hairline: View {
  let inset: CGFloat

  public init(inset: CGFloat = 0) { self.inset = inset }

  public var body: some View {
    Rectangle()
      .fill(Ink.separator)
      .frame(height: 0.5)
      .padding(.leading, inset)
      .accessibilityHidden(true)
  }
}

#Preview("Well") {
  BothSchemes {
    Card {
      VStack(alignment: .leading, spacing: Space.m) {
        Text("Reading corner").font(.ourioHeadline).foregroundStyle(Ink.text)
        HStack(spacing: Space.s) {
          ForEach(0..<4, id: \.self) { _ in
            Color.clear.aspectRatio(1, contentMode: .fit).wellSurface()
          }
        }
        Hairline()
        Text("Complete it for 60 coins").font(.ourioCallout).foregroundStyle(Ink.textSecondary)
      }
    }
    .padding(Space.gutter)
  }
}
