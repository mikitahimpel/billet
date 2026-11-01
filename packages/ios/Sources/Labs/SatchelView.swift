import DesignSystem
import SwiftUI

/// A small satchel with its flap open and nothing in it, drawn in the app's own colours.
struct SatchelShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let (w, h) = (rect.width, rect.height)
    path.addRoundedRect(
      in: CGRect(x: rect.minX + w * 0.1, y: rect.minY + h * 0.35, width: w * 0.8, height: h * 0.6),
      cornerSize: CGSize(width: w * 0.12, height: w * 0.12))
    path.move(to: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.35))
    path.addCurve(
      to: CGPoint(x: rect.minX + w * 0.7, y: rect.minY + h * 0.35),
      control1: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.02),
      control2: CGPoint(x: rect.minX + w * 0.7, y: rect.minY + h * 0.02))
    return path
  }
}

/// Said on Home once the partner has opened the note the cat carried.
public struct CatCameBackRow: View {
  private let catName: String?

  public init(catName: String?) {
    self.catName = catName
  }

  public var body: some View {
    ListRow(
      "\(catName ?? "The cat") is back",
      subtitle: "Your partner opened the note. The satchel is empty."
    ) {
      SatchelShape()
        .fill(Palette.wood.color)
        .overlay { SatchelShape().stroke(Palette.woodLit.color, lineWidth: 1.5) }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    } trailing: {
      EmptyView()
    }
    .card()
    .accessibilityIdentifier("catCameBack")
  }
}
