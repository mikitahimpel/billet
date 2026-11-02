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
  private var isRehearsing = false
  private var awaitingRehearsal: [CheckedContinuation<Void, Never>] = []

  nonisolated init() {}

  /// The kept room, or a new one.
  func diorama() -> NookiDiorama {
    observeMemoryWarnings()
    if let kept { return kept }
    let made = NookiDiorama()
    kept = made
    return made
  }

  func beginRehearsal() {
    isRehearsing = true
  }

  func endRehearsal() {
    isRehearsing = false
    let waiting = awaitingRehearsal
    awaitingRehearsal = []
    for continuation in waiting { continuation.resume() }
  }

  /// Returns once no rehearsal view is left. A RealityView that mounts while another is still
  /// there can stay empty for good, so the room's own view mounts only after this.
  func untilRehearsed() async {
    guard isRehearsing else { return }
    await withCheckedContinuation { awaitingRehearsal.append($0) }
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
