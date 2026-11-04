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
      case .signedOut, .unpaired:
        // One view for both, so the first-launch scene plays on while the account is made.
        RealOnboardingPairing(
          model: model.pairing, scenes: scenes, lighting: lighting,
          signInFailure: anonymousFailure?.message
        ) {
          model.paired()
        }
        .task(id: model.stage) {
          guard model.stage == .signedOut else { return }
          model.anonymous.appeared()
        }
        .task(id: model.anonymous.state) { await signInSettled(model.anonymous.state) }
      case .paired:
        RealPairedView(model: model)
      }
    }
    .preferredColorScheme(.dark)
    .tint(Palette.gold.color)
    .calmAnimation(value: model.stage)
    .alert("Your partner has left billet", isPresented: partnerLeftShown) {
      Button("OK") { model.partnerLeftSeen() }
    } message: {
      Text(Self.partnerLeftMessage)
    }
  }

  static let partnerLeftMessage =
    "They deleted their account, so your pair has ended. The cat stays with you, and you can "
    + "pair again whenever you like."

  private var anonymousFailure: SignInFailure? {
    if case .failed(let failure, _) = model.anonymous.state { failure } else { nil }
  }

  /// A saved session moves on to pairing; a failure tries again after a moment, with no tap.
  private func signInSettled(_ state: AnonymousSignInMachine.State) async {
    switch state {
    case .signedIn:
      if model.stage == .signedOut { model.signedIn() }
    case .failed:
      try? await Task.sleep(for: Self.retrySignInAfter)
      if !Task.isCancelled { model.anonymous.retry() }
    case .idle, .signingIn:
      break
    }
  }

  private static let retrySignInAfter = Duration.seconds(5)

  private var partnerLeftShown: Binding<Bool> {
    Binding(
      get: { model.partnerLeft != nil },
      set: { shown in if !shown { model.partnerLeftSeen() } })
  }
}

/// The paired screen of the real backend: the notes, with the partner's live drawing above them.
/// The two avatars at the top left open "Us", and the save-your-cat card comes up when it is due.
struct RealPairedView: View {
  let model: RealAppModel

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.appEvents) private var events
  @State private var room: LiveRoom?
  @State private var showsUs = false

  var body: some View {
    let history = model.history()
    VStack(spacing: 0) {
      if let room { LivePartnerView(room: room) }
      HistoryView(model: history) { events(.noteOpened(.app)) }
    }
    .safeAreaInset(edge: .top, spacing: Spacing.small) {
      VStack(alignment: .leading, spacing: Spacing.small) {
        Button {
          showsUs = true
        } label: {
          PairAvatars()
            .frame(minWidth: Target.minimum, minHeight: Target.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if model.offersSaveAccount(notesSent: notesSent(history)) {
          SaveAccountCard(
            model: model.link, onLinked: { model.linkedApple() },
            onClose: { model.dismissSaveAccount() }
          )
          .transition(.opacity)
        }
      }
      .padding(.horizontal, Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .sheet(isPresented: $showsUs) {
      RealUsView(model: model) { action in
        showsUs = false
        model.finished(action)
      }
      .billetSheet()
    }
    .task(id: scenePhase == .active) {
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

  private func notesSent(_ history: HistoryModel) -> Int {
    history.records.count { $0.direction == .sent }
  }
}

/// "Us" for the real backend: the two of us, the cat's place, where the account is saved,
/// notifications, the pair and deleting the account, and about.
struct RealUsView: View {
  let model: RealAppModel
  let onFinished: (AccountAction) -> Void

  var body: some View {
    ScreenScaffold("Us") {
      UsHeader(
        me: PairAvatars.me, partner: PairAvatars.partner, catName: nil, daysTogether: nil,
        streak: 0)
      CatCharacterSection(catName: nil)
      AccountSavedSection(linked: model.linked == true) {
        SignInControls(model: model.link) { model.linkedApple() }
      }
      NotificationsSection()
      AccountSections(model: model.account(), onFinished: onFinished)
      AboutSection()
    }
  }
}
