import Ink
import SwiftUI

/// The partner's latest drawing on paper, for the home-screen widget.
public struct LatestNoteView: View {
  public static let paper = Color(red: 0xFB / 255, green: 0xF3 / 255, blue: 0xE4 / 255)

  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public static func loadLatest() -> CGImage? {
    NoteImage.loadLatest()
  }

  public var body: some View {
    if let image {
      Image(decorative: image, scale: 1)
        .resizable()
        .scaledToFit()
    } else {
      Text("No notes yet")
        .foregroundStyle(.black.opacity(0.6))
    }
  }
}

/// The latest drawing in the lock screen's single tint. The ink's alpha is the shape.
public struct NoteSilhouette: View {
  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public var body: some View {
    if let image {
      Image(decorative: image, scale: 1)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
    } else {
      Image(systemName: "scribble")
        .resizable()
        .scaledToFit()
    }
  }
}
