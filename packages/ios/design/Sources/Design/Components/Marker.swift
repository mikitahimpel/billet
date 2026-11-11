import SwiftUI

/// How a drawing's line looks: a thick, slightly glowing marker with a brighter core, so it reads as
/// ink rather than a flat line.
public enum Marker {
  public static func draw(
    _ path: Path, color: Color, width line: CGFloat, in context: inout GraphicsContext
  ) {
    let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
    context.drawLayer { glow in
      glow.addFilter(.shadow(color: color.opacity(0.55), radius: line * 0.55))
      glow.stroke(path, with: .color(color), style: style)
    }
    context.stroke(
      path, with: .color(.white.opacity(0.22)),
      style: StrokeStyle(lineWidth: line * 0.28, lineCap: .round, lineJoin: .round))
  }
}
