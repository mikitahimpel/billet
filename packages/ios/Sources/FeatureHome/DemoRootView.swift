import Delivery
import DesignSystem
import FeatureInbox
import Foundation
import Ink
import Labs
import Payments
import Persistence
import Pet
import PetScene
import SwiftUI
import Transport
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
  @State private var serviceStatus: ServiceStatusModel
  private let updateLink: UpdateLink
  private let publisher = WidgetPublisher.live()
  /// Stamp packs for money, when the build sells them, and the room their purchases are for.
  @State private var stampShop: StampShop?
  private let paymentsLabs: (@MainActor @Sendable () -> AnyView)?
  private let paymentsCaller = DemoPaymentsCaller()

  /// `serviceStatus` asks the demo Worker at `host` for its status (see
  /// ``ServiceStatusModel/demoBaseURL(host:)``), and `updateLink` is where "Update billet" goes.
  public init(
    host: String, scenes: [any PetScene], selectedSceneID: Binding<String?>,
    serviceStatus: ServiceStatusModel, updateLink: UpdateLink,
    payments: (@MainActor (PaymentsServer) -> DemoPayments)? = nil
  ) {
    self.host = host
    DemoRoom.saveHost(host)
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    _serviceStatus = State(initialValue: serviceStatus)
    self.updateLink = updateLink
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
    let caller = paymentsCaller
    let built = ServiceStatusModel.demoBaseURL(host: host).flatMap { baseURL in
      payments?(
        .live(
          .live(
            http: .urlSession(
              baseURL: baseURL, session: .shared, headers: ClientInfo.current().headers),
            caller: .demoRoom { caller.current() })))
    }
    _stampShop = State(initialValue: built.map { StampShop(payments: $0.payments) })
    paymentsLabs = built?.labs
    ScenePerf.mark("root built")
  }

  public var body: some View {
    ServiceStatusLayer(model: serviceStatus, updateLink: updateLink, room: sleepingRoom) {
      content
    }
    .environment(\.eveningGround, model.labs.eveningGround)
    .preferredColorScheme(.dark)
    .tint(Palette.gold.color)
    .calmAnimation(value: model.isPaired)
    .environment(\.labsPayments, labsPayments)
    .onChange(of: model.session.map(ObjectIdentifier.init), initial: true) {
      paymentsCaller.set(model.session?.room.code)
      stampShop?.attach(model.session?.shop)
    }
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
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      await serviceStatus.run()
    }
    .onChange(of: serviceStatus.maintenanceEnds) {
      // A room still backing off reconnects now, and sends what waited in its outbox.
      guard let session = model.session, session.status == .connecting else { return }
      session.disconnect()
      session.connect()
    }
  }

  private var labsPayments: AnyView? {
    guard let stampShop, let shop = model.session?.shop else { return nil }
    return AnyView(PaymentsLabsSection(stampShop: stampShop, shop: shop, extra: paymentsLabs?()))
  }

  /// The chosen scene with its cat asleep, for the maintenance screen.
  private func sleepingRoom() -> AnyView? {
    guard let scene = scenes.first(where: { $0.id == selectedSceneID }) ?? scenes.first else {
      return nil
    }
    return AnyView(SleepingRoom(scene: scene, labs: model.labs))
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
      case _ where !onboarding.isFinished:
        onboardingPairing
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
        onboardingPairing
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

  /// Pairing in the first-launch scene. It is also what shows if the pairing is ever left
  /// unfinished after the scene's own steps are over.
  private var onboardingPairing: some View {
    OnboardingPairingView(
      scenes: scenes, lighting: model.labs.lighting,
      memory: OnboardingMemory.thisLaunch, pairing: onboarding,
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
  }

  private func startChoosing() {
    let model = model
    // Each cat's temperament comes from the pair and the cat, so both phones show the same, and
    // the one adopted is saved for life.
    func seed(_ cat: AdoptionCat) -> UInt64? {
      model.session.map { CatBrainModel.seed(pair: $0.room.code, cat: cat.choice) }
    }
    adoption = AdoptionModel(
      send: { model.session?.adopt($0) },
      adopt: { cat in
        model.labs.setCat(cat.choice)
        if let seed = seed(cat) { _ = model.labs.temperament(forSeed: seed) }
      },
      temperament: { cat in seed(cat).map(CatTemperament.born(seed:)) })
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
