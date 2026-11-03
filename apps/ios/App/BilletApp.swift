import FeatureHome
import Persistence
import PetSceneCatalog
import PetSceneReality
import SwiftUI
import Transport
import WidgetBridge
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
  private let backend = BackendMode(info: Bundle.main.infoDictionary)
  @State private var catalog = PetSceneCatalog(
    scenes: [NookiPetScene()],
    defaults: .standard,
    poses: try? .appGroup(identifier: AppGroupStorage.billetIdentifier),
    onPosesPublished: { WidgetCenter.shared.reloadAllTimelines() }
  )

  init() {
    // Before Home reads the room style.
    if let store = WidgetFeaturesStore.appGroup() {
      FlatSceneMigration.run(
        defaults: .standard, choiceKey: PetSceneCatalog.choiceKey,
        keptSceneID: NookiPetScene().id, store: store)
    }
  }

  var body: some Scene {
    WindowGroup {
      switch backend {
      case .demo:
        DemoRootView(
          host: demoHost,
          scenes: catalog.scenes,
          selectedSceneID: Binding(
            get: { catalog.selectedID },
            set: { id in id.map(catalog.select) }
          ))
      case .real(let baseURL):
        RealRootView(model: RealBackend.model(baseURL: baseURL), scenes: catalog.scenes)
      }
    }
  }
}

/// The real client's services, built only when the build asks for the real backend.
@MainActor
enum RealBackend {
  static func model(baseURL: URL) -> RealAppModel {
    let tokens = SessionTokenStore.keychain(
      client: .security, service: "com.mikitahimpel.billet", accessGroup: nil)
    let storage =
      (try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier))
      ?? .directory(URL.applicationSupportDirectory.appending(path: "Account"))
    let accounts = AccountStore.live(tokens: tokens, storage: storage)
    let api = APIClient.live(
      http: .urlSession(baseURL: baseURL, session: .shared, headers: ClientInfo.current().headers),
      token: { (try? accounts.load())?.token })
    return RealAppModel(api: api, accounts: accounts, baseURL: baseURL)
  }
}
