import CoreGraphics
import Ink
import SwiftUI
import Wire

/// The received drawing, laid exactly over the `NoteNew` node in `LittleHouse.riv`.
///
/// The Rive note is the same on every delivery, so this paper covers it. Sizes and keyframes
/// mirror that node and must change with it.
struct HungNote: View {
  /// Frame 468 of Deliver at 60 fps, when the Rive note first shows.
  static let revealDelay = Duration.seconds(468.0 / 60.0)

  private static let artboard = CGSize(width: 780, height: 980)
  private static let paper = CGRect(x: 336, y: 455, width: 112, height: 138)
  private static let peg = CGPoint(x: 392, y: 446)
  private static let paperColor = Color(red: 0xFB / 255, green: 0xF3 / 255, blue: 0xE4 / 255)

  private struct Swing {
    var scale = 1.0
    var rotation = 0.02
  }

  let drawing: CGImage

  @State private var hasAppeared = false

  var body: some View {
    GeometryReader { geometry in
      let scale = min(
        geometry.size.width / Self.artboard.width, geometry.size.height / Self.artboard.height)
      let left = (geometry.size.width - Self.artboard.width * scale) / 2
      let top = (geometry.size.height - Self.artboard.height * scale) / 2
      let anchor = UnitPoint(
        x: (Self.peg.x - Self.paper.minX) / Self.paper.width,
        y: (Self.peg.y - Self.paper.minY) / Self.paper.height)

      RoundedRectangle(cornerRadius: 4 * scale)
        .fill(Self.paperColor)
        .overlay {
          Image(decorative: drawing, scale: 1)
            .resizable()
            .scaledToFit()
            .padding(4 * scale)
        }
        .frame(width: Self.paper.width * scale, height: Self.paper.height * scale)
        .keyframeAnimator(initialValue: Swing(), trigger: hasAppeared) { content, swing in
          content
            .scaleEffect(swing.scale, anchor: anchor)
            .rotationEffect(.radians(swing.rotation), anchor: anchor)
        } keyframes: { _ in
          KeyframeTrack(\.scale) {
            LinearKeyframe(0.3, duration: 0)
            LinearKeyframe(1.06, duration: 0.3)
            LinearKeyframe(1, duration: 0.2)
          }
          KeyframeTrack(\.rotation) {
            LinearKeyframe(0.22, duration: 0)
            LinearKeyframe(-0.14, duration: 0.4)
            LinearKeyframe(0.08, duration: 0.4)
            LinearKeyframe(-0.03, duration: 0.4)
            LinearKeyframe(0.02, duration: 0.33)
          }
        }
        .position(x: left + Self.paper.midX * scale, y: top + Self.paper.midY * scale)
    }
    .allowsHitTesting(false)
    .accessibilityElement()
    .accessibilityLabel("Received note")
    .onAppear { hasAppeared = true }
  }

  /// A square picture of `strokes`, or `nil` if they cannot be drawn.
  static func image(of strokes: [Stroke], side: Int = 480) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let size = CGSize(width: side, height: side)
    guard (try? StrokeRenderer.draw(fitted(strokes), in: context, size: size)) != nil else {
      return nil
    }
    return context.makeImage()
  }

  /// Scales and centres `strokes` to fill the unit square, because a drawing on the canvas can run
  /// taller than it is wide, or sit small in one corner.
  nonisolated static func fitted(_ strokes: [Stroke]) -> [Stroke] {
    let points = strokes.flatMap(\.points)
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
      let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
    else { return strokes }
    let margin = 0.08
    let span = max(maxX - minX, maxY - minY, 0.05)
    let scale = (1 - 2 * margin) / span
    let offsetX = 0.5 - (minX + maxX) / 2 * scale
    let offsetY = 0.5 - (minY + maxY) / 2 * scale
    return strokes.map { stroke in
      Stroke(
        color: stroke.color,
        width: stroke.width * scale,
        points: stroke.points.map { Point(x: $0.x * scale + offsetX, y: $0.y * scale + offsetY) })
    }
  }
}
