import SwiftUI

/// Progress toward one goal as a bar in a card: a recessed track that fills from the leading edge
/// to `value` of `total`. It reads to VoiceOver as a percentage; the caller gives it a label.
public struct ProgressBar: View {
  let fraction: Double
  let tint: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(value: Double, total: Double = 1, tint: Color = .honey) {
    self.fraction = total > 0 ? min(max(value / total, 0), 1) : 0
    self.tint = tint
  }

  static let height: CGFloat = Space.s

  public var body: some View {
    Capsule()
      .fill(Ink.well)
      .frame(height: Self.height)
      .overlay {
        // Scaled, not resized: the fill moves without laying the card out again.
        Rectangle()
          .fill(tint)
          .scaleEffect(x: fraction, y: 1, anchor: .leading)
      }
      .clipShape(.capsule)
      .animation(reduceMotion ? nil : Motion.spring(), value: fraction)
      .accessibilityElement(children: .ignore)
      .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
  }
}

#Preview("Progress bar") {
  BothSchemes {
    Card {
      VStack(spacing: Space.m) {
        ProgressBar(value: 0)
        ProgressBar(value: 3, total: 8)
        ProgressBar(value: 1, tint: .blushPink)
      }
    }
    .padding(Space.gutter)
  }
}
