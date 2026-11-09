import SwiftUI

/// Screens never pick a raw curve or time.
public enum Motion {
  /// Seconds: a control's own change and a page swapped in place.
  public static let quick: Double = 0.2
  /// Seconds: a larger move that brings in something new.
  public static let standard: Double = 0.35

  /// No overshoot, so nothing settles past where it lands.
  public static func spring(_ duration: Double = standard) -> Animation {
    .spring(duration: duration, bounce: 0)
  }

  /// A page swapped in place, what leaves, and everything under Reduce Motion.
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
