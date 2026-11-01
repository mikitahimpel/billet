import FeatureHome
import Persistence
import PetSceneCatalog
import PetSceneRive
import SwiftUI
import WidgetKit

@main
struct BilletApp: App {
  @State private var catalog = PetSceneCatalog(
    scenes: [LittleHousePetScene()],
    defaults: .standard,
    poses: try? .appGroup(identifier: AppGroupStorage.billetIdentifier),
    onPosesPublished: { WidgetCenter.shared.reloadAllTimelines() }
  )

  var body: some Scene {
    WindowGroup {
      HomeView(
        scenes: catalog.scenes,
        selectedSceneID: Binding(
          get: { catalog.selectedID },
          set: { id in id.map(catalog.select) }
        ))
    }
  }
}
