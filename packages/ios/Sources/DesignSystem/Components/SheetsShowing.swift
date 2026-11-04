import Observation
import SwiftUI

/// How many of the app's sheets show now, each counted by ``SwiftUI/View/billetSheet(_:)`` while
/// it is up. A scene under a sheet is mostly hidden, so it can draw at a gentler pace.
@MainActor @Observable
public final class SheetsShowing {
  public static let shared = SheetsShowing()

  public private(set) var count = 0
  public var any: Bool { count > 0 }

  fileprivate func change(by delta: Int) { count = max(count + delta, 0) }
}

/// Counts its content as a sheet that shows, from when it appears until it disappears.
struct CountsAsSheet: ViewModifier {
  @State private var isCounted = false

  func body(content: Content) -> some View {
    content
      .onAppear {
        guard !isCounted else { return }
        isCounted = true
        SheetsShowing.shared.change(by: 1)
      }
      .onDisappear {
        guard isCounted else { return }
        isCounted = false
        SheetsShowing.shared.change(by: -1)
      }
  }
}
