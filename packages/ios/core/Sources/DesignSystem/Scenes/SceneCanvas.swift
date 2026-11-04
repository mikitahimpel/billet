import SwiftUI

/// Paints a scene at any size, keeping its proportions.
public struct SceneCanvas: View {
  private let art: SceneArt

  public init(_ art: SceneArt) {
    self.art = art
  }

  public var body: some View {
    Canvas { context, size in
      let scale = size.width / art.size.width
      context.scaleBy(x: scale, y: scale)
      for mark in art.marks {
        var layer = context
        layer.opacity = mark.opacity
        switch mark.style {
        case .fill(let evenOdd):
          layer.fill(
            mark.path,
            with: Self.shading(mark.paint),
            style: FillStyle(eoFill: evenOdd)
          )
        case .stroke(let style):
          layer.stroke(mark.path, with: Self.shading(mark.paint), style: style)
        }
      }
    }
    .aspectRatio(art.size, contentMode: .fit)
  }

  private static func shading(_ paint: ScenePaint) -> GraphicsContext.Shading {
    switch paint {
    case .solid(let swatch):
      .color(swatch.color)
    case .linear(let swatches, let start, let end):
      .linearGradient(
        Gradient(colors: swatches.map(\.color)),
        startPoint: start,
        endPoint: end
      )
    case .glow(let swatch, let opacity, let center, let radius):
      .radialGradient(
        Gradient(colors: [swatch.color.opacity(opacity), swatch.color.opacity(0)]),
        center: center,
        startRadius: 0,
        endRadius: radius
      )
    }
  }
}
