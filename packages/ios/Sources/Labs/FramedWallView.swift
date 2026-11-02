import DesignSystem
import FeatureInbox
import Ink
import SwiftUI

/// The framed notes, hung on the wall of the scene: small wooden frames, each with a nail and a
/// slight lean. Touches go through to the scene.
public struct FramedWallView: View {
  private let notes: [NoteRecord]

  @State private var images: [UUID: CGImage] = [:]

  /// - Parameter notes: The notes in their frames, in the order they were hung.
  public init(notes: [NoteRecord]) {
    self.notes = notes
  }

  public var body: some View {
    HStack(alignment: .top, spacing: Spacing.small) {
      ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
        frame(note)
          .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2.5 : 2))
          .transition(.opacity)
      }
    }
    .padding(.top, Spacing.wide)
    .padding(.leading, Spacing.medium)
    .allowsHitTesting(false)
    .task(id: notes.map(\.id)) {
      let wanted = notes
      images = await Task.detached {
        Dictionary(
          uniqueKeysWithValues: wanted.compactMap { note in
            NoteImage.cgImage(of: note.strokes, side: 160).map { (note.id, $0) }
          })
      }.value
    }
    .calmAnimation(value: notes.map(\.id))
  }

  private func frame(_ note: NoteRecord) -> some View {
    VStack(spacing: 0) {
      Circle().fill(Palette.woodDeep.color).frame(width: 5, height: 5)
      RoundedRectangle(cornerRadius: 3)
        .fill(Palette.paper.color)
        .overlay {
          if let image = images[note.id] {
            Image(decorative: image, scale: 1).resizable().scaledToFit().padding(3)
          }
        }
        .frame(width: 46, height: 46)
        .padding(4)
        .background(Palette.wood.color, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Palette.woodLit.color, lineWidth: 1) }
        .shadow(color: Palette.pageDeep.color.opacity(0.5), radius: 2, y: 1)
    }
    .accessibilityElement()
    .accessibilityLabel("Framed note")
  }
}

/// The button under a received note: hang it in a frame, or take it down.
public struct FrameNoteButton: View {
  private let note: NoteRecord
  private let framed: FramedNotes
  @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 260

  public init(note: NoteRecord, framed: FramedNotes) {
    self.note = note
    self.framed = framed
  }

  public var body: some View {
    if FrameWall.canHang(note) {
      let hung = framed.wall.isHung(note.id)
      BilletButton(
        hung ? "Take the frame down" : "Hang in a frame", rank: .secondary,
        systemImage: hung ? "rectangle.slash" : "photo.artframe"
      ) {
        if hung { framed.takeDown(note.id) } else { framed.hang(note) }
      }
      .frame(maxWidth: buttonWidth)
      .padding(.top, Spacing.small)
    }
  }
}

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
