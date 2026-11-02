import DesignSystem
import Ink
import SwiftUI
import WidgetKit

/// The note widget on the home screen: the partner's latest drawing straight on the paper, which
/// is the widget's whole background (see ``PaperSurface``). No frame, card or border.
public struct NotePaperView: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.widgetFamily) private var family

  private let image: CGImage?

  public init(image: CGImage?) {
    self.image = image
  }

  public var body: some View {
    if let image {
      note(image)
    } else {
      empty
    }
  }

  /// In full colour the drawing keeps its own inks. Tinted and clear home screens drop the
  /// paper and flatten colour, so the ink becomes a silhouette in the accent colour instead.
  @ViewBuilder private func note(_ image: CGImage) -> some View {
    Group {
      if renderingMode == .fullColor {
        Image(decorative: NoteImage.trimmedToInk(image), scale: 1)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
      } else {
        NoteSilhouette(image: image)
          .widgetAccentable()
      }
    }
    .padding(margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel("Your partner's drawing")
  }

  private var empty: some View {
    Text("No notes yet")
      .billetType(family == .systemSmall ? .action : .heading)
      .foregroundStyle(renderingMode == .fullColor ? Palette.ink.color : .primary)
      .multilineTextAlignment(.center)
      .minimumScaleFactor(0.7)
      .padding(margin)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetAccentable()
  }

  /// Room round the ink so it never runs into the widget's rounded corners.
  private let margin = Spacing.medium
}
