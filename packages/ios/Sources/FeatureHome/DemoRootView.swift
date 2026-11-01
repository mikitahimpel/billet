import Delivery
import DesignSystem
import FeatureInbox
import Foundation
import Ink
import Persistence
import PetScene
import SwiftUI
import WidgetKit

/// Shows pairing or the tabs, and keeps the room connection open while the app is in front.
public struct DemoRootView: View {
  private static let pairingTimeout = Duration.seconds(15)

  private let host: String
  private let scenes: [any PetScene]
  @Binding private var selectedSceneID: String?

  @Environment(\.scenePhase) private var scenePhase
  @State private var model: AppModel

  public init(host: String, scenes: [any PetScene], selectedSceneID: Binding<String?>) {
    self.host = host
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    // Without the bundled faces SwiftUI falls back to the system font, which still reads fine.
    try? BilletFonts.register()
    _model = State(
      initialValue: AppModel(
        dependencies: AppModel.Dependencies(
          defaults: DemoRoom.sharedDefaults,
          archive: NoteArchive(storage: .directory(Self.notesDirectory)),
          delivery: { room in room.socketURL(host: host).map { .live(url: $0, device: room.device) }
          },
          clearSurfaces: {
            NoteImage.removeLatest()
            WidgetCenter.shared.reloadAllTimelines()
          },
          pairingTimeout: Self.pairingTimeout
        )))
  }

  public var body: some View {
    content
      .preferredColorScheme(.dark)
      .task(id: scenePhase == .active) {
        if scenePhase == .active {
          model.session?.connect()
        } else {
          model.session?.disconnect()
        }
      }
  }

  @ViewBuilder private var content: some View {
    if host.isEmpty {
      ZStack {
        Palette.page.color.ignoresSafeArea()
        Text("This build has no demo host.")
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
      }
    } else {
      switch model.stage {
      case .unpaired, .pairing:
        PairingView(model: model)
      case .paired(let session):
        AppShellView(
          session: session,
          scenes: scenes,
          selectedSceneID: $selectedSceneID,
          onChangeCode: { model.changeCode() },
          onLogOut: { await model.logOut() }
        )
      }
    }
  }

  private static var notesDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Notes", directoryHint: .isDirectory)
  }
}
