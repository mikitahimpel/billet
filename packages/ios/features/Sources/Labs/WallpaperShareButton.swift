import DesignSystem
import FeatureInbox
import SwiftUI

/// Saves or shares a received note as a wallpaper picture: the note on the night sky.
public struct WallpaperShareButton: View {
  @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 260
  private let note: NoteRecord

  public init(note: NoteRecord) {
    self.note = note
  }

  public var body: some View {
    #if canImport(UIKit)
      if note.direction == .received, let image = WallpaperImage.render(strokes: note.strokes),
        let png = UIImage(cgImage: image).pngData(), let preview = UIImage(data: png)
      {
        ShareLink(
          item: Image(uiImage: preview),
          preview: SharePreview("Wallpaper", image: Image(uiImage: preview))
        ) {
          ButtonLabel("Make a wallpaper", rank: .secondary, systemImage: "iphone")
        }
        .billetButton(.secondary)
        .frame(maxWidth: buttonWidth)
      }
    #endif
  }
}
