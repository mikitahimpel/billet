import CoreGraphics
import SwiftUI

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
}
