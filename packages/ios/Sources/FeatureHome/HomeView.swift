import BilletKit
import CoreGraphics
import DesignSystem
import FeatureCanvas
import FeatureInbox
import Foundation
import Ink
import Labs
import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// The main screen: the chosen pet scene, and the way into the canvas.
struct HomeView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// False while the shell shows another tab, so the room pauses and a new room waits to mount.
  @Environment(\.petSceneOnScreen) private var tabShown
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var hungImage: CGImage?
  /// What the card that opened the canvas asked for, in place of the day's usual prompt.
  @State private var cardPrompt: String?
  @State private var hangCount = 0
  @State private var petBounce = false
  @State private var showsStatus = false
  /// The line the status pill shows. It lags ``line`` while a dropped connection waits out its
  /// patience, and keeps its text while the pill fades.
  @State private var shownLine: ConnectionLine?
  @State private var notesSent = 0
  @State private var namingCat = false
  @State private var labsOpen = false
  @State private var shopSheet: HomeShop.Sheet?
  /// Where cues for the cat go. An idle scheduler can send through the same director.
  @State private var director = CatDirector()
  /// Whether the launch's glide into the room is playing. Only the first Home of a cold launch
  /// plays it, and not after the first-launch scene; Home stays alive across tabs.
  @State private var launchPlaying = LaunchCinematic.thisLaunch.claim(
    onboardingPlayed: OnboardingMemory.thisLaunch.introSeen)
  @State private var latestDrawing: CGImage?
  @State private var drawerOpen = false
  @State private var ringsOpen = false
  /// True while the streak's flame covers Home, so the room under it pauses.
  @State private var flameShowing = false
  /// The newest partner's note opened from Home, so the room stops marking it as new.
  @AppStorage("home.openedNote") private var openedNoteID = ""
  /// The partner's meal or game being shown, for a few seconds.
  @State private var shownCare: CatCareNotice?

  let session: PairSession
  let widgetFeatures: WidgetFeaturesModel
  let scene: (any PetScene)?
  let onChangeCode: () -> Void
  let onOpenNotes: () -> Void

  private var store: Store<HomeMachine> { session.store }

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  private var delivery: Int { store.state.pet.world.delivery }

  private var isRenovating: Bool { session.renovator.isRenovating }

  /// Long enough to see the note set off before the system prompt covers it.
  private static let askAfterSending = Duration.seconds(2)

  var body: some View {
    home
      .overlay(alignment: .top) { partnerCareToast }
      .task(id: session.careNotice) { await showPartnerCare() }
      .task(id: NudgeInputs(events: session.life.log.all.count, name: session.play.catName)) {
        await CatNudges.plan(
          life: session.life, temperament: session.brain.temperament,
          name: session.play.catName ?? "Your cat")
      }
      .environment(\.petSceneCat, session.labs.cat)
      .environment(\.petSceneWindowView, session.labs.windowView)
      .environment(\.petSceneLighting, session.labs.lighting)
      .environment(\.petSceneFurniture, session.labs.furniture)
      .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: session.play.petsGiven)
      .sensoryFeedback(.success, trigger: session.treatFalling) { _, falling in falling }
      .modifier(
        HomeShop(
          shop: session.shop, renovator: session.renovator, scene: scene,
          showsButtons: !variant.isFullBleed && !isRenovating, sheet: $shopSheet)
      )
      .task(id: latestReceivedNote?.id) {
        latestDrawing = latestReceivedNote.flatMap { NoteImage.cgImage(of: $0.strokes) }
      }
      .calmAnimation(value: isRenovating)
      #if os(iOS)
        .toolbar(isRenovating ? .hidden : .visible, for: .tabBar)
      #endif
      .task { await DemoPush.registerIfAllowed() }
      .task(id: notesSent) {
        guard notesSent > 0 else { return }
        try? await Task.sleep(for: Self.askAfterSending)
        guard !Task.isCancelled else { return }
        await DemoPush.requestPermission()
      }
      .onReceive(NotificationCenter.default.publisher(for: DemoPush.tokenDidChange)) { _ in
        Task { await session.pushTokenChanged() }
      }
      .task(id: StreakInputs(ledger: session.play.ledger, porch: session.porch.light)) {
        await keepStreakCurrent()
      }
      .task { await keepSealedNotesCurrent() }
      .task(id: session.life.speed) { await session.life.run() }
      .task(id: session.labs.cat) {
        let seed = CatBrainModel.seed(pair: session.room.code, cat: session.labs.cat)
        session.brain.setSeed(seed, temperament: session.labs.temperament(forSeed: seed))
        await session.brain.run()
      }
      .onChange(of: session.shop.state.treatsUsed) { old, new in
        if new > old { session.fed() }
      }
      .overlay {
        HomeLifeLayer(
          session: session, scene: scene, ringsOpen: $ringsOpen,
          onFeed: { giveTreat(on: TreatDay.key(for: .now, calendar: .current)) },
          onPet: pet)
      }
      .overlay(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: Spacing.small) {
          if session.labs.isOn(LabExperiment.lifeDebug) {
            LifeDebugOverlay(model: session.life)
          }
          if session.labs.isOn(LabExperiment.brainDebug) {
            BrainDebugOverlay(brain: session.brain, life: session.life)
          }
        }
        .padding(.top, Spacing.wide * 2)
        .padding(.leading, Spacing.medium)
      }
      .task(id: delivery) {
        guard delivery > 0, let wall = scene?.noteWall else { return }
        hungImage = nil
        await session.trips.noteOnItsWay(catName: session.play.catName, reveal: wall.revealDelay)
        try? await Task.sleep(for: wall.revealDelay)
        guard !Task.isCancelled, let drawing = store.state.hungDrawing else { return }
        hungImage = NoteImage.cgImage(of: drawing)
        hangCount += 1
        await session.trips.noteHung()
      }
      .task(id: line) { await followConnection() }
      #if os(iOS)
        .fullScreenCover(isPresented: canvasPresented, onDismiss: clearCardPrompt) {
          CanvasView(
            prompt: cardPrompt
              ?? DailyPrompt.canvasPrompt(
                features: widgetFeatures.features, day: TreatDay.key(for: .now, calendar: .current)),
            onClose: {
              session.advent.drawingFor = nil
              store.send(.canvasClosed)
            },
            onSend: {
              session.send($0)
              notesSent += 1
            }
          )
        }
      #endif
  }

  /// Tells the pet the shared streak, and again each minute because a day rolling over ends it.
  private func keepStreakCurrent() async {
    while !Task.isCancelled {
      let calendar = Calendar.current
      let today = TreatDay.key(for: .now, calendar: calendar)
      store.send(.pet(.streakChanged(session.streak(today: today, calendar: calendar))))
      try? await Task.sleep(for: .seconds(60))
    }
  }

  /// Opens sealed notes as their time comes while Home is up.
  private func keepSealedNotesCurrent() async {
    while !Task.isCancelled {
      session.openSealedNotes()
      try? await Task.sleep(for: .seconds(5))
    }
  }

  private var canvasPresented: Binding<Bool> {
    Binding(
      get: { store.state.screen == .canvas },
      set: {
        if !$0 {
          session.advent.drawingFor = nil
          store.send(.canvasClosed)
        }
      }
    )
  }

  /// How Home is laid out. Large text keeps the classic layout. Decorating keeps whichever
  /// layout is showing, so the room is arranged where it is.
  private var variant: HomeVariant {
    guard scene != nil, !typeSize.isAccessibilitySize else { return .classic }
    return session.labs.homeVariant
  }

  private var latestReceivedNote: NoteRecord? {
    session.notes.first { $0.direction == .received }
  }

  private var isNoteUnread: Bool {
    guard let note = latestReceivedNote else { return false }
    return note.id.uuidString != openedNoteID
  }

  /// Opens the notes from the note in the room, which counts the newest as read.
  private func openLatestNote() {
    if let note = latestReceivedNote { openedNoteID = note.id.uuidString }
    onOpenNotes()
  }

  @ViewBuilder private var home: some View {
    if variant.isFullBleed, let scene {
      fullBleedHome(scene)
        .overlay { nightOverlay }
        .overlay(alignment: .top) {
          if !isRenovating { roomStatus(problemsOnly: true) }
        }
    } else if let scene, !typeSize.isAccessibilitySize {
      styledHome(scene)
        .overlay { nightOverlay }
        .overlay(alignment: .top) {
          if !isRenovating { roomStatus(problemsOnly: true) }
        }
    } else {
      classicHome
    }
  }

  private func styledHome(_ scene: any PetScene) -> some View {
    let calendar = Calendar.current
    let today = TreatDay.key(for: .now, calendar: calendar)
    return StyledHome(
      scene: AnyView(
        scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
          .lifeRingsPress(session, open: $ringsOpen)
          .id(scene.id)
          .environment(\.petSceneOnScreen, roomShows)
          .environment(\.petSceneRenovator, session.renovator)
          .overlay { catReactions.allowsHitTesting(false) }
          .modifier(LaunchGlide(isPlaying: $launchPlaying))),
      notes: session.notes,
      streak: session.streak(today: today, calendar: calendar),
      isFakePartner: session.isFakePartner,
      isNoteUnread: isNoteUnread,
      onOpenNotes: openLatestNote,
      isDecorating: isRenovating,
      isOpening: launchPlaying,
      onDecorate: { session.renovator.requestOpen() },
      flame: flameHost(scene: scene),
      mood: catMood)
  }

  /// The cat's needs and how it feels, for the paw by the streak and the drawer.
  private var catMood: CatNeedsSnapshot {
    let life = session.life.state
    let feeling =
      session.brain.frame?.feeling
      ?? CatFeeling.of(
        needs: life.needs, mood: life.mood, asleep: life.asleep, sleepy: false,
        temperament: session.brain.temperament, config: session.life.config)
    return CatNeedsSnapshot(
      needs: life.needs, feeling: feeling, name: session.play.catName ?? "Your cat")
  }

  /// "Your partner fed Mochi", under the header for a few seconds.
  @ViewBuilder private var partnerCareToast: some View {
    if let care = shownCare, !isRenovating {
      Text(care.line(catName: session.play.catName))
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .padding(.horizontal, Spacing.medium)
        .frame(minHeight: Target.minimum)
        .floatingGlass()
        .padding(.top, Self.statusTop + Target.minimum + Spacing.small)
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
        .accessibilityIdentifier("partnerCare")
    }
  }

  private func showPartnerCare() async {
    guard let care = session.careNotice else { return }
    withAnimation(Motion.spring) { shownCare = care }
    try? await Task.sleep(for: .seconds(3.5))
    guard !Task.isCancelled else { return }
    withAnimation(Motion.spring) { shownCare = nil }
  }

  /// Whether Home's room is in sight: its tab shows, nothing covers it and the flame is closed.
  private var roomShows: Bool {
    tabShown && store.state.screen == .home && !flameShowing
  }

  /// Opens the streak's flame over Home: works out today's flame, remembers the visit on this
  /// phone, and pauses the room under it while it shows.
  private func flameHost(scene: any PetScene) -> StreakFlameHost {
    StreakFlameHost(
      open: {
        let calendar = Calendar.current
        let now = Date.now
        let today = TreatDay.key(for: now, calendar: calendar)
        let streak = session.streak(today: today, calendar: calendar)
        let newest = session.notes.max { $0.date < $1.date }?.id
        let visit = FlameMemoryStore.visit(
          streak: streak, newestNote: newest,
          key: FlameMemoryStore.key(fakePartner: session.isFakePartner))
        return FlameSceneState(
          flame: StreakFlame(streak: streak),
          today: FlameToday.contributions(
            notes: session.notes, treat: session.play.status(on: today), now: now,
            calendar: calendar),
          visit: visit)
      },
      view: { state, close in
        AnyView(
          StreakFlameCover(scene: scene, state: state, onClose: close)
            .environment(\.petSceneOnScreen, true)
            .environment(\.petSceneWindowView, session.labs.windowView)
            .onAppear { flameShowing = true }
            .onDisappear { flameShowing = false })
      })
  }

  private func fullBleedHome(_ scene: any PetScene) -> some View {
    FullBleedHome(
      variant: variant,
      scene: AnyView(
        scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
          .lifeRingsPress(session, open: $ringsOpen)
          .id(scene.id)
          .environment(\.petSceneOnScreen, tabShown && store.state.screen == .home)
          .environment(\.petSceneRenovator, session.renovator)
          .environment(\.petSceneDrawing, latestDrawing)
          .overlay {
            if !scene.handlesTouches { petTapTarget }
          }
          .overlay {
            if let hungImage, let wall = scene.noteWall {
              HungNote(drawing: hungImage, wall: wall)
                .id(hangCount)
            }
          }
          .overlay { catReactions.allowsHitTesting(false) }
          .modifier(LaunchGlide(isPlaying: $launchPlaying))),
      director: director,
      isFakePartner: session.isFakePartner,
      theirTimeZone: session.lamp.theirs?.timeZoneID.flatMap(TimeZone.init(identifier:)),
      pretendHour: session.labs.pretendHour,
      isOpening: launchPlaying,
      onTreat: { giveTreat(on: TreatDay.key(for: .now, calendar: .current)) },
      isDecorating: isRenovating,
      onDecorate: { session.renovator.requestOpen() },
      drawerOpen: $drawerOpen
    ) {
      drawer(scene)
    }
    .onChange(of: store.state.screen) { drawerOpen = false }
  }

  /// Everything the full-bleed Home keeps off the room: the streak, the shop and the closet, the
  /// room's own controls, and the cards that classic Home shows under it.
  private func drawer(_ scene: any PetScene) -> some View {
    let calendar = Calendar.current
    let today = TreatDay.key(for: .now, calendar: calendar)
    let streak = session.streak(today: today, calendar: calendar)
    return VStack(spacing: Spacing.small) {
      fakePartnerCaption
      CatNeedsCard(catMood)
      HStack(spacing: Spacing.small) {
        Label("\(streak) \(streak == 1 ? "day" : "days")", systemImage: "flame.fill")
          .billetType(.action)
          .foregroundStyle(Palette.paper.color)
          .accessibilityIdentifier("drawerStreak")
        Spacer(minLength: 0)
        if scene.hasShop {
          IconButton("archivebox.fill", label: "Closet") { openShop(.closet) }
        }
      }
      controls
    }
  }

  private func openShop(_ sheet: HomeShop.Sheet) {
    drawerOpen = false
    shopSheet = sheet
  }

  /// Uses a treat from the closet, or gives today's treat when the closet has none.
  private func giveTreat(on day: String) {
    let treat = ShopCatalog.standard.items(in: .treats).first { session.shop.owned($0) > 0 }
    if let treat {
      _ = try? session.shop.use(treat, transaction: session.shop.newTransaction())
    } else {
      session.giveTreat(on: day)
    }
  }

  private var homeBackdrop: some View {
    LinearGradient(
      stops: [
        .init(color: Palette.sky.color, location: 0.2),
        .init(color: Palette.meadow.color, location: 0.75),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }

  private var classicHome: some View {
    ZStack {
      homeBackdrop
      if typeSize.isAccessibilitySize {
        // Large text makes the cards taller than the screen, so they scroll under the scene
        // instead of being squeezed over one another.
        ScrollView {
          VStack(spacing: Spacing.small) {
            petScene
              .frame(maxWidth: .infinity)
              .frame(height: isRenovating ? 480 : 240)
            if !isRenovating {
              controls
                .padding(.horizontal, Spacing.medium)
            }
          }
          .padding(.bottom, Spacing.small)
        }
        .scrollBounceBehavior(.basedOnSize)
      } else {
        VStack(spacing: Spacing.small) {
          petScene
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            .layoutPriority(-1)
            .overlay(alignment: .bottom) { fakePartnerCaption }
          if !isRenovating {
            controls
              .padding(.horizontal, Spacing.medium)
              .transition(.opacity)
          }
        }
        .padding(.bottom, Spacing.small)
      }
    }
    .overlay { nightOverlay }
    .overlay(alignment: .top) { roomStatus(problemsOnly: false) }
  }

  /// Dark over the scene while both lamps are out.
  @ViewBuilder private var nightOverlay: some View {
    if session.labs.isOn(LabExperiment.lightsOut) {
      TimelineView(.everyMinute) { context in
        NightOverlay(night: session.lamp.night(at: context.date))
      }
    }
  }

  @ViewBuilder private var petScene: some View {
    if let scene {
      scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
        .lifeRingsPress(session, open: $ringsOpen)
        .id(scene.id)
        .environment(\.petSceneOnScreen, tabShown && store.state.screen == .home)
        .environment(\.petSceneRenovator, session.renovator)
        .environment(\.petSceneDrawing, hungImage)
        .transition(.opacity)
        .scaleEffect(petBounce && !reduceMotion ? 1.012 : 1)
        .calmAnimation(value: petBounce)
        .overlay {
          if !scene.handlesTouches {
            petTapTarget
          }
        }
        .overlay { catReactions }
        .overlay {
          if let hungImage, let wall = scene.noteWall {
            HungNote(drawing: hungImage, wall: wall)
              .id(hangCount)
          }
        }
    }
  }

  private var controls: some View {
    VStack(spacing: Spacing.small) {
      if session.notes.isEmpty, !session.notesFailedToLoad {
        Text("No notes yet. Draw one from the Notes tab.")
          .billetType(.label)
          .foregroundStyle(Palette.paperTurned.color)
          .multilineTextAlignment(.center)
          .transition(.opacity)
      }
      if typeSize.isAccessibilitySize { fakePartnerNotice }
      catNaming
      latestReceived
      treatPanel
      promptCards
      // The porch light is always there, so the sheet always has a card.
      labsDrawer
    }
    .calmAnimation(value: session.notes.isEmpty)
    .calmAnimation(value: session.play.catName)
  }

  @ViewBuilder private var lampColourCard: some View {
    let colours = session.labs.isOn(LabExperiment.lampColours)
    let goodnight = session.labs.isOn(LabExperiment.lightsOut)
    if colours || goodnight {
      LampColourSection(
        store: session.lamp, catName: session.play.catName, showsColours: colours,
        showsGoodnight: goodnight
      ) { session.lampChanged(out: $0) }
    }
  }

  /// Every experiment card in one sheet, so the scene keeps its room on Home.
  private var labsDrawer: some View {
    Button {
      labsOpen = true
    } label: {
      ListRow("Labs", subtitle: "Cards for the experiments that are on") {
        EmptyView()
      } trailing: {
        RowIcon("chevron.up")
      }
    }
    .buttonStyle(RowButtonStyle())
    .card()
    .accessibilityIdentifier("labsDrawer")
    .sheet(isPresented: $labsOpen) {
      ZStack(alignment: .topTrailing) {
        EveningBackground()
        ScrollView {
          VStack(spacing: Spacing.small) {
            Text("Labs")
              .billetType(.heading)
              .foregroundStyle(Palette.paper.color)
              .padding(.top, Spacing.medium)
            todaysWordCard
            giftCards
            adventCard
            onThisDayCard
            sundayPostCard
            sealedNoteCards
            lampColourCard
            nextVisitCard
            porchLightCard
          }
          .padding(.horizontal, Spacing.medium)
          .padding(.bottom, Spacing.large)
        }
        .scrollBounceBehavior(.basedOnSize)
        IconButton("xmark", label: "Close Labs") { labsOpen = false }
          .padding(Spacing.medium)
      }
      .presentationDetents([.medium, .large])
      .preferredColorScheme(.dark)
    }
  }

  @ViewBuilder private var adventCard: some View {
    if session.labs.isOn(LabExperiment.advent) {
      AdventSection(store: session.advent) { number in
        session.advent.drawingFor = number
        store.send(.canvasOpened)
      }
    }
  }

  @ViewBuilder private var giftCards: some View {
    if session.labs.isOn(LabExperiment.wrappedDelivery) {
      GiftSection(
        gifts: session.gifts, shop: session.shop, catName: session.play.catName,
        onWrap: { session.wrap($0) }, onUnwrap: { session.unwrapGift($0) })
    }
  }

  @ViewBuilder private var onThisDayCard: some View {
    if session.labs.isOn(LabExperiment.onThisDay) {
      OnThisDaySection(notes: session.notes, catName: session.play.catName)
    }
  }

  @ViewBuilder private var nextVisitCard: some View {
    if session.labs.isOn(LabExperiment.nextVisit) {
      NextVisitSection(store: session.visit)
    }
  }

  private var porchLightCard: some View {
    PorchLightSection(store: session.porch)
  }

  @ViewBuilder private var sealedNoteCards: some View {
    if session.labs.isOn(LabExperiment.sealedNote) {
      SealedNoteSection(store: session.sealed, catName: session.play.catName)
    }
  }

  @ViewBuilder private var sundayPostCard: some View {
    if session.labs.isOn(LabExperiment.sundayPost) {
      SundayPostSection(notes: session.notes, catName: session.play.catName)
    }
  }

  @ViewBuilder private var todaysWordCard: some View {
    if session.labs.isOn(LabExperiment.todaysWord) {
      TodaysWordSection(notes: session.notes) { store.send(.canvasOpened) }
    }
  }

  /// Says the partner is scripted without taking any height from the scene.
  @ViewBuilder private var fakePartnerCaption: some View {
    if session.isFakePartner, !isRenovating {
      Text("Fake partner: scripted replies, on this phone only")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.medium)
        .accessibilityIdentifier("fakePartnerNotice")
    }
  }

  /// Said plainly, so nobody takes the scripted replies for a person.
  @ViewBuilder private var fakePartnerNotice: some View {
    if session.isFakePartner {
      Text("Fake partner: the replies are scripted and stay on this phone.")
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .frame(minHeight: Target.minimum)
        .card()
        .accessibilityIdentifier("fakePartnerNotice")
    }
  }

  /// A way to answer the newest note the partner sent.
  @ViewBuilder private var latestReceived: some View {
    if let note = session.notes.first(where: { $0.direction == .received }) {
      ListRow("Latest note", subtitle: "Send something back") {
        EmptyView()
      } trailing: {
        ReactionBar(chosen: session.play.reactions[note.id]) { session.react(to: note, $0) }
      }
      .card()
      .sensoryFeedback(.impact(flexibility: .soft), trigger: session.play.reactions[note.id])
    }
  }

  /// The day's question and doodle, for whichever of the two is switched on.
  @ViewBuilder private var promptCards: some View {
    let day = TreatDay.key(for: .now, calendar: .current)
    if widgetFeatures.isOn(.questionCard) {
      promptCard("Today's question", prompt: DailyPrompt.question(on: day))
    }
    if widgetFeatures.isOn(.doodleCard) {
      promptCard("Doodle prompt", prompt: DailyPrompt.doodle(on: day))
    }
  }

  private func clearCardPrompt() {
    cardPrompt = nil
  }

  private func promptCard(_ title: String, prompt: String) -> some View {
    PromptCard(title: title, prompt: prompt) {
      cardPrompt = prompt
      store.send(.canvasOpened)
    }
  }

  /// The cat's name once the pair has one, or the prompt to choose it.
  @ViewBuilder private var catNaming: some View {
    if let name = session.play.catName {
      Text(name)
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
        .accessibilityIdentifier("catNameLabel")
        .transition(.opacity)
    } else if session.hasConnected {
      Button {
        namingCat = true
      } label: {
        ListRow("Name your cat", subtitle: "Whoever chooses first names it for you both") {
          EmptyView()
        } trailing: {
          RowIcon("chevron.up")
        }
      }
      .buttonStyle(RowButtonStyle())
      .card()
      .transition(.opacity)
      .sheet(isPresented: $namingCat) {
        ZStack {
          EveningBackground()
          NamePanel {
            session.nameCat($0)
            namingCat = false
          }
          .padding(.horizontal, Spacing.medium)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
      }
    }
  }

  /// The cat's middle third. A tap pets it on this phone and tells the partner's.
  private var petTapTarget: some View {
    Color.clear
      .contentShape(Rectangle())
      .padding(.horizontal, Spacing.page)
      .padding(.vertical, Spacing.page * 2)
      .onTapGesture(perform: pet)
      .accessibilityLabel("Pet the cat")
      .accessibilityAddTraits(.isButton)
  }

  private func pet() {
    session.pet()
    petBounce.toggle()
  }

  private func handle(_ event: PetSceneEvent) {
    if let event = PetMachine.Event(event) {
      store.send(.pet(event))
      return
    }
    switch event {
    case .petted: pet()
    case .played: session.played()
    case .fed: session.fed()
    case .shooed: session.shooed()
    case .noteOpened: openLatestNote()
    case .affordances(let room, let weather): session.brain.setRoom(room, weather: weather)
    case .touching(let interaction): session.brain.setLive(interaction)
    case .lightSwitched(let light): session.switchLight(light)
    case .deliveryFinished, .settled: break
    }
  }

  /// What the pair has done today, as the scene shows it.
  private var playState: PetPlayState {
    let calendar = Calendar.current
    let today = Date.now
    let day = TreatDay.key(for: today, calendar: calendar)
    return PetPlayState(
      treat: PetPlayState.Treat(session.play.status(on: day)),
      streak: session.streak(today: day, calendar: calendar),
      petsReceived: session.play.petsReceived,
      room: session.shop.state.layout,
      treatsUsed: session.shop.state.treatsUsed,
      lastTreat: session.shop.state.lastTreat,
      life: session.life.drive,
      lifeNeeds: session.life.state.needs,
      brain: session.brain.frame,
      brainSpeed: session.life.speed,
      light: session.play.roomLight
    )
  }

  private var catReactions: some View {
    ZStack {
      HeartBurst(trigger: session.play.petsGiven)
      HeartBurst(trigger: session.play.petsReceived, tint: Palette.light.color)
        .offset(x: Spacing.wide, y: -Spacing.wide)
      TreatDrop(trigger: session.treatFalling)
      HeartBurst(
        trigger: session.reactionsSeen,
        tint: (session.lastReaction ?? .heart).tint.color,
        symbol: (session.lastReaction ?? .heart).symbol)
    }
  }

  private var treatPanel: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let day = TreatDay.key(for: context.date, calendar: calendar)
      TreatPanel(
        status: session.play.status(on: day),
        streak: session.streak(today: day, calendar: calendar),
        onGive: { session.giveTreat(on: day) }
      )
    }
  }

  /// Shows `shownLine` once it is due, and fades it out when it has been read or the connection is
  /// back. A dropped connection is only named after ``ConnectionLine/patience``.
  private func followConnection() async {
    let alreadyWaiting = showsStatus && shownLine?.waitsBeforeShowing == true
    if line.waitsBeforeShowing, !alreadyWaiting {
      if shownLine?.settles == true { withAnimation(Motion.spring) { showsStatus = false } }
      try? await Task.sleep(for: ConnectionLine.patience)
      guard !Task.isCancelled else { return }
    }
    withAnimation(Motion.spring) {
      shownLine = line
      showsStatus = true
    }
    guard line.settles else { return }
    try? await Task.sleep(for: .seconds(4))
    guard !Task.isCancelled else { return }
    withAnimation(Motion.spring) { showsStatus = false }
  }

  /// How far below the top of the safe area the status pill sits: under the row of buttons and
  /// the streak chip that every Home layout keeps there, never over it.
  static let statusTop = Spacing.small + Target.minimum + Spacing.small

  /// The connection's pill under the header. `problemsOnly` keeps a steady line off a room that
  /// fills the screen, so there the pill only names a problem and fades once it is fixed.
  @ViewBuilder private func roomStatus(problemsOnly: Bool) -> some View {
    if showsStatus, let shown = shownLine, !(problemsOnly && shown.settles) {
      VStack(spacing: Spacing.small) {
        statusPill(shown)
        if shown == .refused {
          BilletButton("Change code", rank: .secondary, action: onChangeCode)
            .frame(maxWidth: 200)
        }
      }
      .padding(.top, Self.statusTop)
      .padding(.horizontal, Spacing.medium)
      .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      .transition(.opacity)
    }
  }

  /// A scene with its own buttons leaves room between them for the short line only.
  private var hasRoomControls: Bool { scene?.handlesTouches == true }

  private func statusPill(_ shown: ConnectionLine) -> some View {
    HStack(spacing: Spacing.small) {
      Circle()
        .fill(Self.statusLight(shown).color)
        .frame(width: Spacing.small, height: Spacing.small)
        .accessibilityHidden(true)
      Text(session.isFakePartner && !hasRoomControls ? "Fake partner · \(shown.text)" : shown.text)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
    }
    .calmAnimation(value: shown)
    .padding(.horizontal, Spacing.medium)
    .frame(minHeight: Target.minimum)
    .floatingGlass()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("connectionStatus")
  }

  private static func statusLight(_ line: ConnectionLine) -> Swatch {
    switch line {
    case .partnerHere: Palette.gold
    case .partnerAway: Palette.muted
    case .connecting, .reconnecting: Palette.woodLit
    case .refused: Palette.clayLit
    }
  }
}

extension ConnectionLine {
  /// A steady state fades away once read. A problem stays on screen.
  fileprivate var settles: Bool {
    switch self {
    case .partnerHere, .partnerAway: true
    case .connecting, .reconnecting, .refused: false
    }
  }
}

extension PetPlayState.Treat {
  fileprivate init(_ status: TreatLedger.Status) {
    switch status {
    case .neither: self = .neither
    case .waitingOnPartner: self = .waitingOnPartner
    case .waitingOnMe: self = .waitingOnMe
    case .fed: self = .fed
    }
  }
}

/// What the cat's nudge is planned from, so it is planned again when either changes.
private struct NudgeInputs: Equatable {
  let events: Int
  let name: String?
}

/// What the streak is worked out from, so it is worked out again when either changes.
private struct StreakInputs: Equatable {
  let ledger: TreatLedger
  let porch: PorchLight?
}
