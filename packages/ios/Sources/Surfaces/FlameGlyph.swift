import DesignSystem
import Pet
import SwiftUI

/// The streak's flame drawn flat, for the widget: two tongues, honey and rose, round a cream core,
/// sized by how far the flame has grown, over a soft glow. With no streak it is a warm ember.
public struct FlameGlyph: View {
  private let flame: StreakFlame

  public init(streak: Int) {
    flame = StreakFlame(streak: streak)
  }

  private static let honey = Color(red: 1, green: 0.76, blue: 0.36)
  private static let rose = Color(red: 1, green: 0.58, blue: 0.5)
  private static let cream = Color(red: 1, green: 0.95, blue: 0.83)
  private static let ember = Color(red: 0.95, green: 0.45, blue: 0.2)

  public var body: some View {
    Canvas { context, size in
      let growth = min(flame.growth, 1)
      let foot = CGPoint(x: size.width / 2, y: size.height * 0.92)
      let tall = size.height * (flame.isEmber ? 0.16 : 0.3 + 0.6 * growth)
      let wide = tall * (0.5 + 0.15 * growth)
      let glow = max(tall, size.height * 0.3) * 1.1
      let glowCentre = CGPoint(x: foot.x, y: foot.y - tall * 0.45)
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: glowCentre.x - glow, y: glowCentre.y - glow, width: glow * 2, height: glow * 2)),
        with: .radialGradient(
          Gradient(colors: [
            Self.honey.opacity(flame.isEmber ? 0.35 : 0.3 + 0.3 * growth), Self.honey.opacity(0),
          ]), center: glowCentre, startRadius: 0, endRadius: glow))
      if flame.isEmber {
        let coal = CGRect(
          x: foot.x - wide * 0.9, y: foot.y - wide * 0.5, width: wide * 1.8, height: wide * 0.7)
        context.fill(Path(ellipseIn: coal), with: .color(Self.ember))
      }
      context.fill(
        Self.tongue(
          foot: CGPoint(x: foot.x - wide * 0.12, y: foot.y), height: tall, width: wide,
          lean: -0.12),
        with: .color(Self.honey.opacity(0.92)))
      context.fill(
        Self.tongue(
          foot: CGPoint(x: foot.x + wide * 0.12, y: foot.y), height: tall * 0.94, width: wide,
          lean: 0.12),
        with: .color(Self.rose.opacity(0.88)))
      context.fill(
        Self.tongue(foot: foot, height: tall * 0.55, width: wide * 0.5, lean: 0),
        with: .color(Self.cream))
    }
    .accessibilityElement()
    .accessibilityLabel(flame.stage.title)
  }

  /// A teardrop standing on `foot`, `height` tall and `width` across, its tip pushed sideways by
  /// `lean` of its height.
  static func tongue(foot: CGPoint, height: CGFloat, width: CGFloat, lean: CGFloat) -> Path {
    let tip = CGPoint(x: foot.x + lean * height, y: foot.y - height)
    let half = width / 2
    var path = Path()
    path.move(to: tip)
    path.addCurve(
      to: CGPoint(x: foot.x, y: foot.y),
      control1: CGPoint(x: foot.x + half * 0.4 + lean * height * 0.5, y: foot.y - height * 0.55),
      control2: CGPoint(x: foot.x + half * 1.3, y: foot.y))
    path.addCurve(
      to: tip,
      control1: CGPoint(x: foot.x - half * 1.3, y: foot.y),
      control2: CGPoint(x: foot.x - half * 0.4 + lean * height * 0.5, y: foot.y - height * 0.55))
    path.closeSubpath()
    return path
  }
}
