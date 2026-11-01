import DesignSystem
import Ink
import SwiftUI
import WidgetKit

/// The partner's latest drawing on paper, under the evening sky, for the home-screen widget.
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
    HStack(spacing: Spacing.medium) {
      sheet
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Sparkle()
          .fill(Palette.gold.color)
          .frame(width: 14, height: 14)
          .widgetAccentable()
        Text(image == nil ? "No notes yet" : "Latest note")
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
          .minimumScaleFactor(0.7)
        Text(image == nil ? "Your partner's drawings land here" : "From your partner")
          .billetType(.caption)
          .foregroundStyle(Palette.paperTurned.color)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
    }
  }

  /// Tinted home screens flatten colour, so the paper drops away and the ink carries the shape.
  @ViewBuilder private var sheet: some View {
    if renderingMode == .fullColor {
      RoundedRectangle(cornerRadius: Radius.paper)
        .fill(Palette.paper.color)
        .overlay {
          if let image {
            Image(decorative: image, scale: 1)
              .resizable()
              .scaledToFit()
              .padding(Spacing.hair)
          }
        }
        .aspectRatio(1, contentMode: .fit)
        .rotationEffect(.degrees(-2))
        .lampGlow()
        .accessibilityLabel(image == nil ? "Empty paper" : "Your partner's drawing")
    } else {
      NoteSilhouette(image: image)
        .aspectRatio(1, contentMode: .fit)
        .widgetAccentable()
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
      LockHouseGlyph()
        .aspectRatio(1, contentMode: .fit)
    }
  }
}
