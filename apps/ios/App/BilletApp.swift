import FeatureHome
import Persistence
import PetSceneCatalog
import PetSceneReality
import PetSceneRive
import SwiftUI
import WidgetKit

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
  @State private var catalog = PetSceneCatalog(
    scenes: [LittleHousePetScene(), NookiPetScene(), RooftopPetScene()],
    defaults: .standard,
    poses: try? .appGroup(identifier: AppGroupStorage.billetIdentifier),
    onPosesPublished: { WidgetCenter.shared.reloadAllTimelines() }
  )

  var body: some Scene {
    WindowGroup {
      DemoRootView(
        host: demoHost,
        scenes: catalog.scenes,
        selectedSceneID: Binding(
          get: { catalog.selectedID },
          set: { id in id.map(catalog.select) }
        ))
    }
  }
}
