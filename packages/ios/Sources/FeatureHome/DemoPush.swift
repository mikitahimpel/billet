import Delivery
import Foundation
import UserNotifications

#if os(iOS)
  import UIKit
#endif

/// Registration for the alert the room sends when a note cannot reach this device's socket.
public enum DemoPush {
  static let tokenDidChange = Notification.Name("DemoPush.tokenDidChange")

  @MainActor
  static func requestPermission() async {
    let center = UNUserNotificationCenter.current()
    guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
      return
    }
    #if os(iOS)
      UIApplication.shared.registerForRemoteNotifications()
    #endif
  }

  public static func tokenReceived(_ token: Data) {
    DemoRoom.savePushToken(token.map { String(format: "%02x", $0) }.joined())
    NotificationCenter.default.post(name: tokenDidChange, object: nil)
  }
}
