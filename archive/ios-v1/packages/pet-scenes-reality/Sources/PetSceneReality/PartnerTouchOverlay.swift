import SwiftUI

/// The partner's pet, shown here: a soft, see-through hand strokes the cat twice and a heart
/// rises, each time `trigger` counts up.
struct PartnerTouchOverlay: View {
  let trigger: Int
  /// Where the cat is on screen when the pet arrives.
  let point: () -> CGPoint?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown: (at: CGPoint, start: Date)?

  static let length: TimeInterval = 2.2

  var body: some View {
    TimelineView(.animation(paused: shown == nil)) { context in
      if let shown {
        let t = min(context.date.timeIntervalSince(shown.start) / Self.length, 1)
        // Two strokes along the back, fading in and out.
        let stroke = reduceMotion ? 0.5 : (t * 2).truncatingRemainder(dividingBy: 1)
        let fade = sin(.pi * t)
        ZStack {
          Image(systemName: "hand.raised.fill")
            .font(.system(size: 46))
            .rotationEffect(.degrees(-70))
            .foregroundStyle(.white.opacity(0.55 * fade))
            .blur(radius: 1.5)
            .shadow(color: Color(red: 1, green: 0.6, blue: 0.7).opacity(0.6 * fade), radius: 10)
            .position(x: shown.at.x - 40 + 80 * stroke, y: shown.at.y - 18 + 8 * sin(.pi * stroke))
          Image(systemName: "heart.fill")
            .font(.system(size: 18))
            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.55).opacity(fade))
            .position(x: shown.at.x + 26, y: shown.at.y - 50 - (reduceMotion ? 0 : 40 * t))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: trigger) {
      guard let at = point() else { return }
      shown = (at, .now)
    }
    .task(id: trigger) {
      try? await Task.sleep(for: .seconds(Self.length))
      if let shown, Date.now.timeIntervalSince(shown.start) >= Self.length { self.shown = nil }
    }
  }
}
