import DesignSystem
import SwiftUI

/// What the season puts on the scene: an autumn or blossom branch from the top corner, a drift of
/// snow along the sill, or a low sun. Drawn over the scene, and touches go through.
public struct SeasonOverlay: View {
  private let look: Season.Look

  public init(look: Season.Look) {
    self.look = look
  }

  public var body: some View {
    ZStack {
      switch look.season {
      case .autumn:
        branch(
          count: Season.leaves(look), colours: [Palette.clayLit, Palette.woodLit, Palette.light],
          shape: .leaf
        )
        .frame(width: 170, height: 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      case .spring:
        branch(
          count: Season.blossoms(look), colours: [Palette.paper, Palette.paperTurned],
          shape: .blossom
        )
        .frame(width: 170, height: 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      case .winter:
        snow(depth: Season.snowDepth(look))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      case .summer:
        sun
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private enum Mark { case leaf, blossom }

  private func branch(count: Int, colours: [Swatch], shape: Mark) -> some View {
    Canvas { context, size in
      var stem = Path()
      stem.move(to: CGPoint(x: size.width + 4, y: 6))
      stem.addCurve(
        to: CGPoint(x: size.width * 0.12, y: size.height * 0.55),
        control1: CGPoint(x: size.width * 0.75, y: size.height * 0.1),
        control2: CGPoint(x: size.width * 0.4, y: size.height * 0.5))
      context.stroke(
        stem, with: .color(Palette.woodShade.color),
        style: StrokeStyle(lineWidth: 4, lineCap: .round))
      for index in 0..<count {
        // Evenly spread along the branch, alternating above and below it.
        let t = (Double(index) + 0.5) / 9
        let x = size.width * (0.95 - t * 0.85)
        let y = size.height * (0.12 + t * 0.4) + (index.isMultiple(of: 2) ? 10 : -4)
        let colour = colours[index % colours.count].color
        let rect = CGRect(x: x - 8, y: y - 6, width: 16, height: shape == .leaf ? 11 : 16)
        let angle = Angle.degrees(Double(index * 37 % 90) - 30)
        var local = context
        local.translateBy(x: rect.midX, y: rect.midY)
        local.rotate(by: angle)
        let centred = CGRect(
          x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        local.fill(Path(ellipseIn: centred), with: .color(colour))
        if shape == .blossom {
          local.fill(
            Path(ellipseIn: CGRect(x: -2, y: -2, width: 4, height: 4)),
            with: .color(Palette.light.color))
        }
      }
    }
  }

  private func snow(depth: Double) -> some View {
    Capsule()
      .fill(Palette.paper.color.opacity(0.92))
      .frame(height: 6 + 16 * depth)
      .padding(.horizontal, Spacing.medium)
      .shadow(color: Palette.pageDeep.color.opacity(0.3), radius: 3, y: -1)
  }

  private var sun: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [Palette.light.color.opacity(0.9), Palette.light.color.opacity(0)],
          center: .center, startRadius: 4, endRadius: 70)
      )
      .frame(width: 140, height: 140)
      .offset(x: 40, y: -40)
  }
}
