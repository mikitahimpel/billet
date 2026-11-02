import SwiftUI

/// Every core component on the page ground, for previews and snapshots.
public struct ComponentGallery: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.large) {
      Text(verbatim: "A little house").billetType(.display)
      Text(verbatim: "Reply to Mira").billetType(.title)
      Text(verbatim: "Mira hung a note").billetType(.heading)
      Text(verbatim: "Keep going and the house grows.").billetType(.body)
      Text(verbatim: "On your wall").billetType(.label).foregroundStyle(Palette.muted.color)
      HStack(spacing: Spacing.small) {
        IconButton("pencil", label: "Pen", isSelected: true) {}
        IconButton("arrow.uturn.backward", label: "Undo") {}
        InkSwatch(Palette.ink.color, name: "Ink", isSelected: false) {}
        InkSwatch(Palette.greenLit.color, name: "Green", isSelected: true) {}
      }
      BilletButton("Send to Mira", rank: .primary) {}
      BilletButton("Not now", rank: .secondary) {}
      ListRow("Room", subtitle: "Window Seat") {
        EmptyView()
      } trailing: {
        EmptyView()
      }
      .card()
      ToggleRow("Cat mood", subtitle: "How the cat feels right now.", isOn: .constant(true))
        .card()
      HStack(spacing: Spacing.large) {
        HousePlate(47)
        LockHouseGlyph()
          .fill(Palette.paper.color, style: FillStyle(eoFill: true))
          .frame(width: 56, height: 56)
        SceneCanvas(TinyHouseArt.art).frame(width: 80)
      }
      NoteCard {
        SceneCanvas(SampleDrawing.art)
      }
      .frame(width: 150, height: 119)
    }
    .foregroundStyle(Palette.paper.color)
    .padding(Spacing.wide)
    .frame(width: 430)
    .background(Palette.page.color)
  }
}

#Preview("Components") {
  ComponentGallery()
}

#Preview("Room, medium widget") {
  RoomScene(name: "Mira", streak: 47) {
    SceneCanvas(SampleDrawing.art)
  }
  .frame(width: 338, height: 158)
}

#Preview("House, every stage") {
  ScrollView {
    VStack(spacing: Spacing.medium) {
      ForEach(HouseStage.allCases, id: \.self) { stage in
        ScenePanel {
          HouseScene(streak: stage.firstDay) {
            SceneCanvas(SampleDrawing.art)
          }
        }
      }
    }
    .padding(Spacing.medium)
  }
  .background(Palette.page.color)
}
