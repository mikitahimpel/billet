import FeatureHome
import Persistence
import PetScene
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
  private let updateLink = UpdateLink(info: Bundle.main.infoDictionary)
  /// The demo Worker's maintenance, minimum build and notice. Unused by the real client, which
  /// asks its own backend.
  @State private var demoStatus: ServiceStatusModel
  @State private var catalog = PetSceneCatalog(
    scenes: [NookiPetScene()],
    defaults: .standard,
    poses: try? .appGroup(identifier: AppGroupStorage.billetIdentifier),
    onPosesPublished: { WidgetCenter.shared.reloadAllTimelines() }
  )

  init() {
    ScenePerf.start()
    let client = ClientInfo.current()
    _demoStatus = State(
      initialValue: ServiceStatusModel(
        appVersion: client.appVersion,
        fetch: ServiceStatusModel.demoBaseURL(host: demoHost).map {
          ServiceStatusModel.fetch(baseURL: $0, headers: client.headers)
        },
        memory: .defaults(.standard),
        strings: ServiceStatusModel.strings(in: .main)))
    RetiredLabsMigration.run(defaults: .standard)
    // Before Home reads the scene choice.
    if let store = WidgetFeaturesStore.appGroup() {
      RemovedScenesMigration.run(
        defaults: .standard, choiceKey: PetSceneCatalog.choiceKey,
        keptSceneID: NookiPetScene.sceneID, store: store)
    }
    ScenePerf.mark("app built")
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
          ),
          serviceStatus: demoStatus,
          updateLink: updateLink)
      case .real(let baseURL):
        RealRootView(
          model: RealBackend.model(baseURL: baseURL), scenes: catalog.scenes,
          updateLink: updateLink)
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
    let client = ClientInfo.current()
    let http = HTTPService.urlSession(baseURL: baseURL, session: .shared, headers: client.headers)
    let serviceStatus = ServiceStatusModel(
      appVersion: client.appVersion,
      fetch: ServiceStatusModel.fetch(baseURL: baseURL, headers: client.headers),
      memory: .defaults(.standard),
      strings: ServiceStatusModel.strings(in: .main))
    // Any request that meets the maintenance 503 tells the status at once.
    let api = APIClient.live(
      http: http.reportingMaintenance { status in await serviceStatus.received(status) },
      token: { (try? accounts.load())?.token })
    let keys = AccountKeyStore.keychain(client: .security, service: "com.mikitahimpel.billet")
    return RealAppModel(
      api: api, accounts: accounts, keys: keys, baseURL: baseURL, serviceStatus: serviceStatus)
  }
}
