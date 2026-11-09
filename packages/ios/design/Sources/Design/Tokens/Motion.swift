import SwiftUI

/// The app's one motion scale: two durations and one spring. Screens never pick a raw curve or time.
public enum Motion {
  /// Seconds: a control's own change and a page swapped in place (a selection following the finger, a tab's
  /// page, a fade out of what leaves).
  public static let quick: Double = 0.2
  /// Seconds: a larger move that brings in something new, such as a panel or a card opening.
  public static let standard: Double = 0.35

  /// The one spring, without overshoot, so nothing settles past where it lands.
  public static func spring(_ duration: Double = standard) -> Animation {
    .spring(duration: duration, bounce: 0)
  }

  /// Opacity alone: a page swapped in place, what leaves, and everything under Reduce Motion.
  public static func fade(_ duration: Double = quick) -> Animation {
    .easeInOut(duration: duration)
  }
}

#Preview {
  @Previewable @State var page = 0
  BothSchemes {
    VStack(spacing: Space.l) {
      ZStack {
        Text("Page \(page + 1)")
          .font(.ourioTitle)
          .foregroundStyle(Ink.text)
          .id(page)
          .transition(.opacity)
      }
      .frame(height: 60)
      Button("Next") { withAnimation(Motion.fade()) { page = (page + 1) % 3 } }
    }
    .padding()
  }
}
