import SwiftUI

/// The house at a stage, with the streak on its door and the latest note on its wall.
public struct HouseScene<Note: View>: View {
  private let streak: Int
  private let note: Note

  public init(streak: Int, @ViewBuilder note: () -> Note) {
    self.streak = streak
    self.note = note()
  }

  public var body: some View {
    let stage = HouseStage(streak: streak)
    SceneCanvas(HouseArt.art(for: stage))
      .overlay {
        GeometryReader { geometry in
          let scale = geometry.size.width / HouseArt.size.width
          NoteCard { note }
            .frame(
              width: HouseArt.noteFrame.width * scale,
              height: HouseArt.noteFrame.height * scale
            )
            .rotationEffect(.degrees(HouseArt.noteTilt))
            .position(
              x: HouseArt.noteFrame.midX * scale,
              y: HouseArt.noteFrame.midY * scale
            )
          HousePlate(streak, scale: scale * 1.1)
            .position(
              x: HouseArt.plateCenter.x * scale,
              y: HouseArt.plateCenter.y * scale
            )
          if stage == .chimney {
            Text(verbatim: "\(HouseStage.newRoom.firstDay)")
              .font(.custom(BilletFonts.monoFamily, fixedSize: 34 * scale))
              .foregroundStyle(Palette.gold.color)
              .position(
                x: HouseArt.nextRoomLabelCenter.x * scale,
                y: HouseArt.nextRoomLabelCenter.y * scale
              )
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: "A small house at night, \(streak) days in a row"))
  }
}
