import Delivery
import Foundation
import UserNotifications
import WidgetKit

/// Puts the note a push points at on the widget. The alert shows whether or not that works.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
  private let lock = NSLock()
  private var showAlert: (() -> Void)?
  private var work: Task<Void, Never>?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    let content = request.content
    lock.withLock { showAlert = { contentHandler(content) } }
    guard let noteURL = content.userInfo["noteURL"] as? String, let room = DemoRoom.saved() else {
      finish()
      return
    }
    let work = Task { [self] in
      if await room.saveNote(noteURL: noteURL) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      finish()
    }
    lock.withLock { self.work = work }
  }

  override func serviceExtensionTimeWillExpire() {
    lock.withLock { work }?.cancel()
    finish()
  }

  private func finish() {
    let show = lock.withLock {
      defer { showAlert = nil }
      return showAlert
    }
    show?()
  }
}
