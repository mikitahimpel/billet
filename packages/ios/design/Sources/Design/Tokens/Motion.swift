import SwiftUI

/// The app's one motion scale: two durations and one spring. Screens never pick a raw curve or time.
public enum Motion {
  /// Seconds: a control's own change and a page swapped in place (a selection moving, a tab's page, a fade
  /// out of what leaves).
  public static let quick: Double = 0.2
  /// Seconds: a larger move that brings in something new, such as a panel or a card opening.
  public static let standard: Double = 0.35
  /// Points a page travels on its way in, along the order of the control it was picked from.
  public static let shift: CGFloat = 10

  /// The one spring, without overshoot, so nothing settles past where it lands.
  public static func spring(_ duration: Double = standard) -> Animation {
    .spring(duration: duration, bounce: 0)
  }

  /// A move that ends exactly at `duration`, fast out and settling in like the spring. For what animates on
  /// every switch (a tab's page, the selection pill): a spring keeps updating long after it looks still.
  public static func move(_ duration: Double = quick) -> Animation {
    .timingCurve(0.2, 0.9, 0.3, 1, duration: duration)
  }

  /// Opacity alone, for what leaves and for everything under Reduce Motion.
  public static func fade(_ duration: Double = quick) -> Animation {
    .easeOut(duration: duration)
  }

  /// Which way a change moves along an ordered control, such as a tab bar or a segmented control.
  public enum Direction: Equatable, Sendable {
    case forward, backward, still

    public init(from old: Int, to new: Int) {
      self = new > old ? .forward : new < old ? .backward : .still
    }
  }

  /// The horizontal offset a page arriving in `direction` starts at: from the side it lies on, none under
  /// Reduce Motion.
  public static func entryOffset(_ direction: Direction, reduceMotion: Bool) -> CGFloat {
    guard !reduceMotion else { return 0 }
    switch direction {
    case .forward: return shift
    case .backward: return -shift
    case .still: return 0
    }
  }
}

extension AnyTransition {
  /// A page swapped for another in place: the new one fades in on `Motion.move` from `Motion.entryOffset`,
  /// the old one fades out quick. Opacity and a drawn offset only: neither page's frame moves, so nothing in it
  /// lays out again on the way.
  public static func page(_ direction: Motion.Direction, reduceMotion: Bool) -> AnyTransition {
    .asymmetric(
      insertion: AnyTransition(
        PageEntry(offset: Motion.entryOffset(direction, reduceMotion: reduceMotion))
      )
      .animation(Motion.move()),
      removal: .opacity.animation(Motion.fade()))
  }
}

/// Fades in from `offset` points to the side. The offset is applied when drawing (`visualEffect`), not to the
/// frame, as `.offset` would: a moving frame updates the geometry of everything inside it every frame.
private struct PageEntry: Transition {
  let offset: CGFloat

  func body(content: Content, phase: TransitionPhase) -> some View {
    let x = phase.isIdentity ? 0 : offset
    content
      .opacity(phase.isIdentity ? 1 : 0)
      .visualEffect { view, _ in view.offset(x: x) }
  }
}

#Preview {
  @Previewable @State var page = 0
  BothSchemes {
    VStack(spacing: Space.l) {
      ZStack {
        Text("Page \(page + 1)")
          .font(.nookiTitle)
          .foregroundStyle(Ink.text)
          .id(page)
          .transition(.page(.forward, reduceMotion: false))
      }
      .frame(height: 60)
      Button("Next") { withAnimation(Motion.spring()) { page = (page + 1) % 3 } }
    }
    .padding()
  }
}
