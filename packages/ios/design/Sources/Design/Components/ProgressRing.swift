import SwiftUI

/// A ring that fills clockwise from the top to `value` (0…1), round-capped, around `center`. Drawn
/// as one trimmed circle; it animates only when `value` changes.
public struct ProgressRing<Center: View>: View {
  let value: Double
  let tint: Color
  let center: Center
  @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 88
  @ScaledMetric(relativeTo: .title2) private var line: CGFloat = Space.s

  public init(value: Double, tint: Color = .honey, @ViewBuilder center: () -> Center) {
    self.value = value
    self.tint = tint
    self.center = center()
  }

  public var body: some View {
    ZStack {
      // The tint's own faint track, so an empty ring still reads as waiting to fill, not as off.
      Circle()
        .stroke(tint.opacity(0.22), lineWidth: line)
      Circle()
        .trim(from: 0, to: min(max(value, 0), 1))
        .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
        .rotationEffect(.degrees(-90))
      center
    }
    .padding(line / 2)
    .frame(width: side, height: side)
    .animation(.snappy(duration: 0.4), value: value)
  }
}

#Preview("Progress ring") {
  BothSchemes {
    HStack(spacing: Space.l) {
      ProgressRing(value: 0.1) { Text("1").font(.ourioTitle) }
      ProgressRing(value: 6.0 / 7) { Text("6").font(.ourioTitle) }
      ProgressRing(value: 1, tint: .blushPink) { Image(systemName: "checkmark") }
    }
    .padding(Space.gutter)
  }
}
