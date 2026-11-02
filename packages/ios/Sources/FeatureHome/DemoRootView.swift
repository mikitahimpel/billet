import Delivery
import DesignSystem
import FeatureInbox
import Foundation
import Ink
import Persistence
import PetScene
import SwiftUI
import WidgetBridge
import WidgetKit

/// Shows pairing or the tabs, and keeps the room connection open while the app is in front.
public struct DemoRootView: View {
  private static let pairingTimeout = Duration.seconds(15)

  private let host: String
  private let scenes: [any PetScene]
  @Binding private var selectedSceneID: String?

  @Environment(\.scenePhase) private var scenePhase
  @State private var model: AppModel
  @State private var widgetFeatures: WidgetFeaturesModel
  private let publisher = WidgetPublisher.live()

  public init(host: String, scenes: [any PetScene], selectedSceneID: Binding<String?>) {
    self.host = host
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    // Without the bundled faces SwiftUI falls back to the system font, which still reads fine.
    try? BilletFonts.register()
    // Widget features and lab experiments share one file, so they share the one model that saves it.
    let features = WidgetFeaturesModel(store: .appGroup()) {
      WidgetCenter.shared.reloadAllTimelines()
      #if os(iOS)
        ControlCenter.shared.reloadAllControls()
      #endif
    }
    _widgetFeatures = State(initialValue: features)
    _model = State(
      initialValue: AppModel(
        dependencies: AppModel.Dependencies(
          defaults: DemoRoom.sharedDefaults,
          archive: NoteArchive(storage: .directory(Self.notesDirectory)),
          delivery: { room in room.socketURL(host: host).map { .live(url: $0, device: room.device) }
          },
          clearSurfaces: {
            NoteImage.removeLatest()
            WidgetSnapshotStore.appGroup()?.remove()
            WidgetCenter.shared.reloadAllTimelines()
          },
          pairingTimeout: Self.pairingTimeout,
          labs: features,
          fakeArchive: NoteArchive(storage: .directory(Self.fakeNotesDirectory))
        )))
  }

  public var body: some View {
    content
      .environment(\.eveningGround, model.labs.eveningGround)
      .preferredColorScheme(.dark)
      .tint(Palette.gold.color)
      .calmAnimation(value: model.isPaired)
      .onChange(of: model.labs.isOn(LabExperiment.fakePartner)) { _, on in
        model.fakePartnerSwitched(on: on)
      }
      .task(id: scenePhase == .active) {
        if scenePhase == .active {
          model.session?.connect()
        } else {
          model.session?.disconnect()
        }
      }
  }

  @ViewBuilder private var content: some View {
    if host.isEmpty, !model.isFakePartner {
      ZStack {
        EveningBackground()
        VStack(spacing: Spacing.medium) {
          Text("This build has no demo host.")
            .billetType(.body)
            .foregroundStyle(Palette.paper.color)
          BilletButton("Try alone with a fake partner", rank: .secondary) {
            model.labs.set(LabExperiment.fakePartner, on: true)
          }
        }
        .padding(.horizontal, Spacing.medium)
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
          widgetFeatures: widgetFeatures,
          publisher: publisher,
          labs: model.labs,
          onChangeCode: { model.changeCode() },
          onLogOut: { await model.logOut() }
        )
      }
    }
  }

  private static var fakeNotesDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "FakePartnerNotes", directoryHint: .isDirectory)
  }

  private static var notesDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Notes", directoryHint: .isDirectory)
  }
}
