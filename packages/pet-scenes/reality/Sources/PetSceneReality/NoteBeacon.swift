import SwiftUI

/// A note that has not been opened yet, marked on the note itself: a warm glow that breathes
/// around its paper and a gold dot on its top corner. Still when motion is reduced.
struct NoteBeacon: View {
  /// The note's paper as the camera sees it, or empty before the room has been fitted.
  let outline: [CGPoint]
  let isPaused: Bool

  /// One breath, in seconds.
  static let period = 2.8
  static let gold = Color(red: 1, green: 0.78, blue: 0.36)

  var body: some View {
    if outline.count >= 3 {
      TimelineView(.animation(minimumInterval: 1 / 30, paused: isPaused)) { context in
        let breath = isPaused ? 1 : Self.breath(at: context.date.timeIntervalSinceReferenceDate)
        ZStack {
          glow(opacity: 0.45 + 0.4 * breath)
          dot
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  /// From 0 to 1 and back, easing at both ends.
  static func breath(at time: TimeInterval) -> Double {
    0.5 - 0.5 * cos(time * 2 * .pi / period)
  }

  private var paper: Path {
    var path = Path()
    path.addLines(outline)
    path.closeSubpath()
    return path
  }

  private var size: CGFloat {
    let xs = outline.map(\.x)
    let ys = outline.map(\.y)
    return min((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
  }

  private func glow(opacity: Double) -> some View {
    let width = max(size * 0.12, 6)
    return paper
      .stroke(Self.gold, style: StrokeStyle(lineWidth: width, lineJoin: .round))
      .blur(radius: width)
      .opacity(opacity)
      .blendMode(.screen)
  }

  /// On the corner furthest up and right, where a badge sits on an app icon.
  @ViewBuilder private var dot: some View {
    if let corner = outline.max(by: { $0.x - $0.y < $1.x - $1.y }) {
      let diameter = min(max(size * 0.1, 8), 12)
      Circle()
        .fill(Self.gold)
        .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
        .frame(width: diameter, height: diameter)
        .shadow(color: Self.gold.opacity(0.8), radius: diameter / 2)
        .position(corner)
    }
  }
}
