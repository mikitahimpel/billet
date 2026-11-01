import DesignSystem
import SwiftUI

/// A small heart that floats up and fades each time `trigger` changes.
///
/// A SwiftUI overlay, so it works over any scene.
public struct HeartBurst: View {
  private let trigger: Int
  private let tint: Color
  @State private var hearts: [Int] = []

  public init(trigger: Int, tint: Color = Palette.clayLit.color) {
    self.trigger = trigger
    self.tint = tint
  }

  public var body: some View {
    ZStack {
      ForEach(hearts, id: \.self) { id in
        FloatingHeart(tint: tint, drift: CGFloat((id % 5) - 2) * Spacing.small)
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
  let drift: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var risen = false

  var body: some View {
    Image(systemName: "heart.fill")
      .font(IconStyle.font)
      .scaleEffect(risen ? 1.4 : 1)
      .foregroundStyle(tint)
      .offset(x: drift, y: risen && !reduceMotion ? -Spacing.page : 0)
      .opacity(risen ? 0 : 1)
      .onAppear { withAnimation(.easeOut(duration: 1.5)) { risen = true } }
  }
}
