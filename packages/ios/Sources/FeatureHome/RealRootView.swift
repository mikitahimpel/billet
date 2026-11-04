import DesignSystem
import FeatureCanvas
import FeatureInbox
import FeatureOnboarding
import FeaturePairing
import FeatureSettings
import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// The app when `BackendMode` is `real`: sign in, pair, then the paired screens.
public struct RealRootView: View {
  @State private var model: RealAppModel
  private let scenes: [any PetScene]
  private let lighting: RoomLighting
  private let updateLink: UpdateLink

  @Environment(\.scenePhase) private var scenePhase

  /// `scenes` give the first-launch scene; with none, signing in and pairing happen over the
  /// evening background instead, with the same words and controls. `updateLink` is where
  /// "Update billet" goes.
  public init(
    model: RealAppModel, scenes: [any PetScene] = [], updateLink: UpdateLink = .testFlight
  ) {
    _model = State(initialValue: model)
    self.scenes = scenes
    self.updateLink = updateLink
    lighting = WidgetFeaturesStore.appGroup()?.loadLighting() ?? .standard
    try? BilletFonts.register()
  }

  public var body: some View {
    ServiceStatusLayer(model: model.serviceStatus, updateLink: updateLink, room: sleepingRoom) {
      stages
    }
    .preferredColorScheme(.dark)
    .tint(Palette.gold.color)
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      await model.serviceStatus.run()
    }
    .onChange(of: model.serviceStatus.maintenanceEnds) {
      Task { await model.maintenanceEnded() }
    }
    .onChange(of: model.serviceStatus.analyticsEnabled) { model.analyticsChanged() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { Task { await model.enteredBackground() } }
    }
    .environment(\.appEvents, model.events)
  }

  /// The first scene with its cat asleep, for the maintenance screen.
  private func sleepingRoom() -> AnyView? {
    guard let scene = scenes.first else { return nil }
    return AnyView(SleepingRoom(scene: scene, labs: model.labs))
  }

  private var stages: some View {
    Group {
      switch model.stage {
      case .signedOut:
        CinematicOnboardingView(
          scenes: scenes, lighting: lighting, memory: OnboardingMemory.thisLaunch
        ) {
          SignInControls(model: model.signIn) { model.signedIn() }
        }
      case .unpaired:
        RealOnboardingPairing(model: model.pairing, scenes: scenes, lighting: lighting) {
          model.paired()
        }
      case .paired:
        RealPairedView(model: model)
      }
    }
    .preferredColorScheme(.dark)
    .tint(Palette.gold.color)
    .calmAnimation(value: model.stage)
  }
}

/// The screens of a paired account: the notes, with the partner's live drawing above them, and
/// the account settings.
struct RealPairedView: View {
  let model: RealAppModel

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.appEvents) private var events
  @State private var room: LiveRoom?

  var body: some View {
    TabView {
      Tab("Notes", systemImage: "tray") {
        VStack(spacing: 0) {
          if let room { LivePartnerView(room: room) }
          HistoryView(model: model.history()) { events(.noteOpened(.app)) }
        }
      }
      Tab("Settings", systemImage: "gearshape") {
        AccountSettingsView(model: model.account()) { model.finished($0) }
      }
    }
    .task(id: scenePhase == .active) {
      let history = model.history()
      if scenePhase == .active {
        Task { await model.becameActive() }
        history.refresh()
        await history.settled()
        let live = model.live(lastSeq: history.lastSeq) { _, _ in history.refresh() }
        room = live
        live.connect()
      } else {
        room?.disconnect()
      }
    }
  }
}
