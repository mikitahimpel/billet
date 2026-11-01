import FeatureHome
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    DemoPush.tokenReceived(deviceToken)
  }
}

@main
struct BilletApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let demoHost = Bundle.main.object(forInfoDictionaryKey: "BilletDemoHost") as? String ?? ""

  var body: some Scene {
    WindowGroup {
      DemoRootView(host: demoHost)
    }
  }
}
