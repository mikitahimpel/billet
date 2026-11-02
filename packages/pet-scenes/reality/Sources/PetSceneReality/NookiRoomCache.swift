import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// Keeps the loaded room while the scene is away, so coming back costs a view and not a load.
/// One view shows the room at a time. A memory warning lets go of a room that is off screen.
@MainActor
final class NookiRoomCache {
  private var kept: NookiDiorama?
  private var memoryWarnings: (any NSObjectProtocol)?

  nonisolated init() {}

  /// The kept room, or a new one.
  func diorama() -> NookiDiorama {
    observeMemoryWarnings()
    if let kept { return kept }
    let made = NookiDiorama()
    kept = made
    return made
  }

  func purgeIfOffScreen() {
    if kept?.isOnScreen == false { kept = nil }
  }

  private func observeMemoryWarnings() {
    #if canImport(UIKit)
      guard memoryWarnings == nil else { return }
      memoryWarnings = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.purgeIfOffScreen() }
      }
    #endif
  }
}
