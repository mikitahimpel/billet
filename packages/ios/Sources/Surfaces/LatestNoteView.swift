import DesignSystem
import Ink
import SwiftUI
import WidgetKit

/// The partner's latest drawing as large as the widget allows: warm paper filling the evening
/// ground, concentric with the widget's own corners.
public struct LatestNoteView: View {
  @Environment(\.widgetRenderingMode) private var renderingMode

  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public static func loadLatest() -> CGImage? {
    NoteImage.loadLatest()
  }

  public var body: some View {
    if let image {
      note(image)
    } else {
      empty
    }
  }

  /// Tinted home screens flatten colour, so the paper drops away and the ink carries the shape.
  @ViewBuilder private func note(_ image: CGImage) -> some View {
    if renderingMode == .fullColor {
      ContainerRelativeShape()
        .fill(Palette.paper.color)
        .overlay {
          Image(decorative: NoteImage.trimmedToInk(image), scale: 1)
            .resizable()
            .scaledToFit()
            .padding(Spacing.small)
        }
        .padding(Spacing.small)
        .accessibilityLabel("Your partner's drawing")
    } else {
      NoteSilhouette(image: image)
        .padding(Spacing.medium)
        .widgetAccentable()
    }
  }

  private var empty: some View {
    VStack(spacing: Spacing.small) {
      Sparkle()
        .fill(Palette.gold.color)
        .frame(width: Spacing.medium, height: Spacing.medium)
        .widgetAccentable()
      Text("No notes yet")
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
        .minimumScaleFactor(0.7)
    }
    .multilineTextAlignment(.center)
    .padding(Spacing.medium)
  }
}

/// The latest drawing in the lock screen's single tint, cropped to its ink so it fills the space.
/// The ink's alpha is the shape.
public struct NoteSilhouette: View {
  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public var body: some View {
    if let image {
      Image(decorative: NoteImage.trimmedToInk(image), scale: 1)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
    } else {
      LockHouseGlyph()
        .fill(style: FillStyle(eoFill: true))
        .aspectRatio(1, contentMode: .fit)
    }
  }
}

/// The rectangular lock-screen widget, the largest Apple allows: the drawing fills all of it.
public struct LockNoteRectangular: View {
  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public var body: some View {
    if image == nil {
      HStack(spacing: Spacing.small) {
        NoteSilhouette(image: nil)
          .widgetAccentable()
        Text("No notes yet")
          .billetType(.action)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    } else {
      NoteSilhouette(image: image)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetAccentable()
        .accessibilityLabel("New note from your partner")
    }
  }
}

/// The circular lock-screen widget: the drawing alone on the system's ring. A word at this size
/// would be too small to read.
public struct LockNoteCircular: View {
  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public var body: some View {
    ZStack {
      AccessoryWidgetBackground()
      NoteSilhouette(image: image)
        .padding(Spacing.small)
        .widgetAccentable()
    }
    .accessibilityLabel(image == nil ? "No notes yet" : "New note from your partner")
  }
}
