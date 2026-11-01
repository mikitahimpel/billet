import FeatureHome
import SwiftUI

@main
struct BilletApp: App {
  private let demoHost = Bundle.main.object(forInfoDictionaryKey: "BilletDemoHost") as? String ?? ""

  var body: some Scene {
    WindowGroup {
      DemoRootView(host: demoHost)
    }
  }
}
