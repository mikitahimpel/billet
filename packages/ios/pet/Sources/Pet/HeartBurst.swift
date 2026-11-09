import DesignSystem
import SwiftUI

/// A small mark, a heart unless told otherwise, that floats up and fades each time `trigger`
/// changes. A SwiftUI overlay, so it works over any scene.
public struct HeartBurst: View {
  private let trigger: Int
  private let tint: Color
  private let symbol: String
  @State private var hearts: [Int] = []

  public init(trigger: Int, tint: Color = Palette.clayLit.color, symbol: String = "heart.fill") {
    self.trigger = trigger
    self.tint = tint
    self.symbol = symbol
  }

  public var body: some View {
    ZStack {
      ForEach(hearts, id: \.self) { id in
        FloatingHeart(tint: tint, symbol: symbol, drift: CGFloat((id % 5) - 2) * Spacing.small)
          .transition(.identity)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: trigger) { _, new in
      hearts.append(new)
      Task {
        try? await Task.sleep(for: .seconds(1.6))
        hearts.removeAll { $0 == new }
      }
    }
  }
}

private struct FloatingHeart: View {
  let tint: Color
  let symbol: String
  let drift: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var risen = false

  var body: some View {
    Image(systemName: symbol)
      .font(IconStyle.font)
      .scaleEffect(risen ? 1.4 : 1)
      .foregroundStyle(tint)
      .offset(x: drift, y: risen && !reduceMotion ? -Spacing.page : 0)
      .opacity(risen ? 0 : 1)
      .onAppear { withAnimation(.easeOut(duration: 1.5)) { risen = true } }
  }
}
