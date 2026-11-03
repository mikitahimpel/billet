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
  /// The first-launch scene's pairing: held past the pairing itself, until the joined moment
  /// has been shown.
  @State private var onboarding: OnboardingPairing
  /// Choosing the cat together, once the pair was made in the first-launch scene.
  @State private var adoption: AdoptionModel?
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
    _onboarding = State(initialValue: OnboardingPairing(paired: _model.wrappedValue.isPaired))
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
      .onChange(of: pairingFacts, initial: true) { _, facts in
        // Logged out: the next pairing gets the scene again.
        if facts == .unpaired, onboarding.isFinished { onboarding = OnboardingPairing() }
        onboarding.observe(facts)
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
      case _ where !onboarding.isFinished && model.labs.isOn(LabExperiment.cinematicOnboarding):
        OnboardingPairingView(
          scenes: scenes, lighting: model.labs.lighting,
          memory: OnboardingMemory(defaults: DemoRoom.sharedDefaults), pairing: onboarding,
          failure: model.failure?.message,
          actions: OnboardingPairingActions(
            create: { model.createPair() },
            join: { model.join(code: $0) },
            cancel: { model.cancelPairing() },
            goIn: { model.finishCreating() },
            tryAlone: { model.labs.set(LabExperiment.fakePartner, on: true) }),
          send: { event in
            let wasJoined = if case .joined = onboarding.step { true } else { false }
            onboarding.send(event)
            guard onboarding.isFinished else { return }
            if wasJoined { startChoosing() }
            model.finishCreating()
          })
      case .paired(let session) where adoption != nil:
        if let adoption {
          AdoptionView(
            scenes: scenes, lighting: model.labs.lighting, model: adoption,
            catName: session.play.catName, rename: { session.renameCat($0) },
            onDone: { self.adoption = nil }
          )
          .onAppear {
            adoption.partnerPresence(session.status == .partnerHere)
            session.onAdoption = { [weak adoption] in adoption?.received($0) }
          }
          .onChange(of: session.status) { _, status in
            adoption.partnerPresence(status == .partnerHere)
          }
          .onDisappear { session.onAdoption = nil }
          .transition(.opacity)
        }
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

  private func startChoosing() {
    let model = model
    adoption = AdoptionModel(
      send: { model.session?.adopt($0) },
      adopt: { model.labs.setCat($0.choice) })
  }

  /// Where the pairing is, as the first-launch scene follows it.
  private var pairingFacts: OnboardingPairing.Facts {
    switch model.stage {
    case .unpaired: .unpaired
    case .pairing(let session, creating: true):
      .creating(
        code: session.room.code, live: session.hasConnected,
        partnerHere: session.status == .partnerHere)
    case .pairing(_, creating: false): .joining
    case .paired: .paired
    }
  }

  private static var fakeNotesDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "FakePartnerNotes", directoryHint: .isDirectory)
  }

  private static var notesDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Notes", directoryHint: .isDirectory)
  }
}
