import SwiftUI

public struct CoinIcon: View {
  var size: CGFloat

  public init(size: CGFloat = 16) { self.size = size }

  public var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [Color(hex: 0xFFE07A), Color(hex: 0xF0A92E)], startPoint: .top,
            endPoint: .bottom))
      Image(systemName: "star.fill")
        .font(.system(size: size * 0.42, weight: .bold))
        .foregroundStyle(Color(hex: 0xC97C14))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
