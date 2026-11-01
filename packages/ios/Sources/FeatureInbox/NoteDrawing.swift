import CoreGraphics
import DesignSystem
import Ink
import SwiftUI
import Wire

/// A note's drawing on its sheet of paper. The picture is rendered off the main actor.
struct NoteDrawing: View {
  let note: NoteRecord
  /// Pixel side of the rendered picture.
  let side: Int

  @State private var image: CGImage?

  var body: some View {
    RoundedRectangle(cornerRadius: Radius.paper)
      .fill(Palette.paper.color)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .task(id: note.id) {
        let strokes = note.strokes
        let side = side
        image = await Task.detached { NoteImage.render(strokes, side: side) }.value
      }
  }
}
