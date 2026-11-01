import CoreGraphics
import DesignSystem
import PetScene
import SwiftUI

/// The received drawing, laid exactly over the note a scene hangs on its wall.
///
/// The scene's note is the same on every delivery, so this paper covers it.
struct HungNote: View {

  private struct Swing {
    var scale = 1.0
    var rotation = 0.02
  }

  let drawing: CGImage
  let wall: PetSceneNoteWall

  @State private var hasAppeared = false

  var body: some View {
    GeometryReader { geometry in
      let scale = min(
        geometry.size.width / wall.artboard.width, geometry.size.height / wall.artboard.height)
      let left = (geometry.size.width - wall.artboard.width * scale) / 2
      let top = (geometry.size.height - wall.artboard.height * scale) / 2
      let anchor = UnitPoint(
        x: (wall.peg.x - wall.paper.minX) / wall.paper.width,
        y: (wall.peg.y - wall.paper.minY) / wall.paper.height)

      RoundedRectangle(cornerRadius: 4 * scale)
        .fill(Palette.paper.color)
        .overlay {
          Image(decorative: drawing, scale: 1)
            .resizable()
            .scaledToFit()
            .padding(4 * scale)
        }
        .frame(width: wall.paper.width * scale, height: wall.paper.height * scale)
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
        .position(x: left + wall.paper.midX * scale, y: top + wall.paper.midY * scale)
    }
    .allowsHitTesting(false)
    .accessibilityElement()
    .accessibilityLabel("Received note")
    .onAppear { hasAppeared = true }
  }
}
