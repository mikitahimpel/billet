import SwiftUI

/// A poster on a shelf that scrolls sideways: the art full bleed on top, the name and one status
/// line under it. `emphasis` tints the status when it asks something of the viewer ("Your turn").
public struct PosterCard: View {
  let title: String
  let status: String
  let emphasis: Bool
  let art: Image
  let action: () -> Void

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
          .aspectRatio(4 / 5, contentMode: .fit)
          .overlay { art.resizable().scaledToFill() }
          .clipped()
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Space.xs) {
          Text(title)
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
          Text(status)
            .font(.ourioCallout.weight(emphasis ? .semibold : .regular))
            .foregroundStyle(emphasis ? Ink.accentText : Ink.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.m)
        .padding([.horizontal, .bottom], CardMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
