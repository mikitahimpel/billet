import DesignSystem
import SwiftUI

/// A cat's paw: one pad and four toes, drawn in the unit box.
struct PawPrint: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let (w, h) = (rect.width, rect.height)
    path.addEllipse(
      in: CGRect(x: rect.minX + w * 0.2, y: rect.minY + h * 0.5, width: w * 0.6, height: h * 0.46))
    for (x, y, size) in [
      (0.02, 0.36, 0.22), (0.24, 0.1, 0.24), (0.54, 0.1, 0.24), (0.76, 0.36, 0.22),
    ] {
      path.addEllipse(
        in: CGRect(
          x: rect.minX + w * x, y: rect.minY + h * y, width: w * size, height: h * size * 1.2))
    }
    return path
  }
}

/// The cat's place while it is away: the cushion with a warm dent in it, and paw prints leading
/// off. Decorative; the words come from ``OvernightStayCaption``.
public struct OvernightStayView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = 0

  public init() {}

  public var body: some View {
    ZStack {
      cushion
      HStack(spacing: Spacing.small) {
        ForEach(0..<4, id: \.self) { index in
          PawPrint()
            .fill(Palette.woodLit.color.opacity(0.55))
            .frame(width: 18, height: 20)
            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -14 : 14))
            .offset(y: index.isMultiple(of: 2) ? -6 : 6)
            .opacity(reduceMotion || index < shown ? 1 : 0)
        }
      }
      .offset(x: 84, y: -4)
    }
    .frame(width: 250, height: 90)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task {
      guard !reduceMotion else { return }
      shown = 0
      for step in 1...4 {
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(Motion.spring) { shown = step }
      }
    }
  }

  private var cushion: some View {
    ZStack {
      Ellipse().fill(Palette.raised.color)
      Ellipse().stroke(Palette.lightWarm.color.opacity(Glow.edgeOpacity), lineWidth: 1)
      Ellipse()
        .fill(
          RadialGradient(
            colors: [Palette.pageDeep.color.opacity(0.7), Palette.raised.color.opacity(0)],
            center: .center, startRadius: 2, endRadius: 46)
        )
        .frame(width: 96, height: 44)
        .offset(x: -6, y: 2)
      Ellipse()
        .fill(Palette.light.color.opacity(0.12))
        .frame(width: 60, height: 24)
        .offset(x: -6, y: 0)
    }
    .frame(width: 160, height: 74)
    .offset(x: -42)
  }
}

/// What the Home screen says while the cat is away.
public enum OvernightStayCaption {
  public static func title(catName: String?) -> String {
    "\(catName ?? "The cat") is at your partner's"
  }

  public static func detail(catName: String?) -> String {
    "The cushion is still warm. \(catName ?? "The cat") comes back when they draw you one."
  }
}
