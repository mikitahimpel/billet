import SwiftUI

/// The streak, as the number on the house. It is the only way a streak is shown, so it always
/// brings its own dark ground and clears contrast on any wall.
public struct HousePlate: View {
  private let number: Int
  private let scale: CGFloat

  /// - Parameter scale: Multiplies the plate's natural size when it stands inside a scene.
  public init(_ number: Int, scale: CGFloat = 1) {
    self.number = number
    self.scale = scale
  }

  public var body: some View {
    Text(verbatim: "\(number)")
      .font(.custom(BilletFonts.monoFamily, fixedSize: 26 * scale))
      .foregroundStyle(Palette.gold.color)
      .padding(.horizontal, 10 * scale)
      .frame(minWidth: 56 * scale, minHeight: 38 * scale)
      .background(Palette.plate.color, in: .rect(cornerRadius: Radius.scenePlate * scale))
      .overlay {
        RoundedRectangle(cornerRadius: (Radius.scenePlate - 2) * scale)
          .strokeBorder(Palette.gold.color, lineWidth: 1.2 * scale)
          .padding(2 * scale)
      }
      .accessibilityLabel(Text("\(number) days in a row", bundle: .module))
  }
}
