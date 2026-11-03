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
  /// Whether signing in happens in the first-launch scene, as Labs sets it.
  private let isCinematic: Bool
  private let lighting: RoomLighting

  /// `scenes` give the first-launch scene; with none, or with the Labs switch off, it is the
  /// plain welcome.
  public init(model: RealAppModel, scenes: [any PetScene] = []) {
    _model = State(initialValue: model)
    self.scenes = scenes
    let store = WidgetFeaturesStore.appGroup()
    isCinematic =
      !scenes.isEmpty
      && (store?.load() ?? WidgetFeatures()).isOn(LabExperiment.cinematicOnboarding)
    lighting = store?.loadLighting() ?? .standard
    try? BilletFonts.register()
  }

  public var body: some View {
    Group {
      switch model.stage {
      case .signedOut where isCinematic:
        CinematicOnboardingView(
          scenes: scenes, lighting: lighting, memory: OnboardingMemory(defaults: .standard)
        ) {
          SignInControls(model: model.signIn) { model.signedIn() }
        }
      case .signedOut:
        OnboardingView(model: model.signIn) { model.signedIn() }
      case .unpaired where isCinematic:
        RealOnboardingPairing(model: model.pairing, scenes: scenes, lighting: lighting) {
          model.paired()
        }
      case .unpaired:
        PairingFlowView(model: model.pairing) { model.paired() }
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
  @State private var room: LiveRoom?

  var body: some View {
    TabView {
      Tab("Notes", systemImage: "tray") {
        VStack(spacing: 0) {
          if let room { LivePartnerView(room: room) }
          HistoryView(model: model.history())
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
