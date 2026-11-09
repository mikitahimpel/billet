import Ink
import SwiftUI
import Design
import Wire

/// Strokes drawn as a thick, slightly glowing marker. Coordinates and widths are fractions of the layer's width, as
/// strokes carry them, so the same drawing fills any phone.
public struct InkLayer: View {
    public let strokes: [Stroke]

    public init(strokes: [Stroke]) {
        self.strokes = strokes
    }

    public var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                InkLayer.draw(stroke, in: &context, width: size.width)
            }
        }
        .allowsHitTesting(false)
    }

    public static func draw(_ stroke: Stroke, in context: inout GraphicsContext, width: CGFloat) {
        guard !stroke.points.isEmpty, let hex = UInt32(stroke.color.dropFirst(), radix: 16) else { return }
        let color = Color(hex: hex)
        let line = stroke.width * width
        let path = Path(SmoothPath.path(stroke.points, scale: width))
        let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        context.drawLayer { glow in
            glow.addFilter(.shadow(color: color.opacity(0.55), radius: line * 0.55))
            glow.stroke(path, with: .color(color), style: style)
        }
        // A brighter core makes it read as marker ink rather than a flat line.
        context.stroke(path, with: .color(.white.opacity(0.22)),
                       style: StrokeStyle(lineWidth: line * 0.28, lineCap: .round, lineJoin: .round))
    }
}
