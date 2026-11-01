import SwiftUI

/// A sheet of paper held by two pegs. Whatever was drawn goes on it, loose, in its own hand.
public struct NoteCard<Drawing: View>: View {
  private let drawing: Drawing

  public init(@ViewBuilder drawing: () -> Drawing) {
    self.drawing = drawing()
  }

  public var body: some View {
    GeometryReader { geometry in
      let peg = CGSize(
        width: max(5, geometry.size.width * 0.047),
        height: max(12, geometry.size.width * 0.12)
      )
      ZStack(alignment: .top) {
        RoundedRectangle(cornerRadius: Radius.paper)
          .fill(Palette.paper.color)
          .shadow(color: Palette.plate.color.opacity(0.4), radius: 2, x: 2, y: 3)
        drawing
          .padding(.horizontal, geometry.size.width * 0.02)
          .clipped()
        HStack {
          pegShape(peg)
          Spacer()
          pegShape(peg)
        }
        .padding(.horizontal, geometry.size.width * 0.2)
        .offset(y: -peg.height / 2)
      }
    }
  }

  private func pegShape(_ size: CGSize) -> some View {
    RoundedRectangle(cornerRadius: 1.5)
      .fill(Palette.woodLit.color)
      .frame(width: size.width, height: size.height)
  }
}
