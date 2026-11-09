import SwiftUI

public struct RoomScene<Note: View>: View {
  private let name: String
  private let streak: Int
  private let note: Note

  public init(name: String, streak: Int, @ViewBuilder note: () -> Note) {
    self.name = name
    self.streak = streak
    self.note = note()
  }

  public var body: some View {
    SceneCanvas(RoomArt.art)
      .overlay {
        GeometryReader { geometry in
          let scale = geometry.size.width / RoomArt.size.width
          NoteCard { note }
            .frame(
              width: RoomArt.noteFrame.width * scale,
              height: RoomArt.noteFrame.height * scale
            )
            .rotationEffect(.degrees(RoomArt.noteTilt))
            .position(x: RoomArt.noteFrame.midX * scale, y: RoomArt.noteFrame.midY * scale)
          Text(name)
            .font(.custom(BilletFonts.groteskFamily, fixedSize: 17 * scale).weight(.bold))
            .foregroundStyle(Palette.paper.color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 64 * scale)
            .position(x: RoomArt.nameCenter.x * scale, y: RoomArt.nameCenter.y * scale)
          HousePlate(streak, scale: scale)
            .position(x: RoomArt.plateFrame.midX * scale, y: RoomArt.plateFrame.midY * scale)
          Text("days", bundle: .module)
            .font(.custom(BilletFonts.groteskFamily, fixedSize: 13 * scale).weight(.medium))
            .foregroundStyle(Palette.paper.color)
            .position(x: RoomArt.captionCenter.x * scale, y: RoomArt.captionCenter.y * scale)
        }
      }
      .accessibilityElement(children: .combine)
  }
}
