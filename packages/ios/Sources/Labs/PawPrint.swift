import SwiftUI

/// A cat's paw: one pad and four toes, drawn in the unit box.
struct PawPrint: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let (w, h) = (rect.width, rect.height)
    path.addEllipse(
      in: CGRect(x: rect.minX + w * 0.2, y: rect.minY + h * 0.5, width: w * 0.6, height: h * 0.46))
    for (x, y, size) in [
      (0.02, 0.36, 0.22), (0.24, 0.1, 0.24), (0.54, 0.1, 0.24), (0.76, 0.36, 0.22),
    ] {
      path.addEllipse(
        in: CGRect(
          x: rect.minX + w * x, y: rect.minY + h * y, width: w * size, height: h * size * 1.2))
    }
    return path
  }
}
