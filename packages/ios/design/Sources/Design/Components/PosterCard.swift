import SwiftUI

/// A poster on a shelf that scrolls sideways: the art full bleed and square on top, the name and one status
/// line under it. `emphasis` tints the status when it asks something of the viewer ("Your turn").
public struct PosterCard: View {
  let title: String
  let status: String
  let emphasis: Bool
  let art: Image
  let action: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  public init(
    _ title: String, status: String, emphasis: Bool = false, art: Image,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.status = status
    self.emphasis = emphasis
    self.art = art
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear
          // Wider at accessibility sizes, where posters stack full width and the words need the room.
          .aspectRatio(typeSize.isAccessibilitySize ? 3 / 2 : 1, contentMode: .fit)
          // Height from the width alone, so long words under it never squeeze the art narrower than the card.
          .fixedSize(horizontal: false, vertical: true)
          .overlay(alignment: .top) { art.resizable().scaledToFill() }
          .clipped()
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Space.xs) {
          Text(title)
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(status)
            .font(.ourioCallout.weight(emphasis ? .semibold : .regular))
            .foregroundStyle(emphasis ? Ink.accentText : Ink.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.m)
        .padding([.horizontal, .bottom], CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .cardSurface()
      .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
      .contentShape(.rect(cornerRadius: Radius.card))
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityElement(children: .combine)
  }
}

#Preview("Poster card") {
  BothSchemes {
    HStack(alignment: .top, spacing: Space.m) {
      PosterCard(
        "Who knows who", status: "Your turn, 3 left", emphasis: true,
        art: Image(systemName: "questionmark.square.fill")
      ) {}
      PosterCard("Draw & guess", status: "Alex is drawing", art: Image(systemName: "pencil")) {}
    }
    .padding(Space.gutter)
  }
}
