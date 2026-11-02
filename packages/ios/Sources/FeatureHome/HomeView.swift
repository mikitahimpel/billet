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
  private static let drawButton = "draw"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @Namespace private var zoom
  @State private var hungImage: CGImage?
  /// What the card that opened the canvas asked for, in place of the day's usual prompt.
  @State private var cardPrompt: String?
  @State private var hangCount = 0
  @State private var petBounce = false
  @State private var showsStatus = true
  @State private var notesSent = 0
  @State private var namingCat = false
  @State private var labsOpen = false
  @State private var shopSheet: HomeShop.Sheet?
  /// Where cues for the cat go. An idle scheduler can send through the same director.
  @State private var director = CatDirector()
  /// Whether the cinematic opening has played since launch. Home stays alive across tabs.
  @State private var hasOpened = false
  @State private var latestDrawing: CGImage?
  @State private var drawerOpen = false

  let session: PairSession
  let widgetFeatures: WidgetFeaturesModel
  let scene: (any PetScene)?
  let onChangeCode: () -> Void
  let onOpenNotes: () -> Void

  private var store: Store<HomeMachine> { session.store }

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  /// The cat is with the partner: the last note on this device is one it sent.
  private var catAway: Bool {
    session.labs.isOn(LabExperiment.overnightStay)
      && OvernightStay.place(after: session.notes).isAway
  }

  /// The notes in frames, in the order they were hung.
  private var framedNotes: [NoteRecord] {
    session.frames.wall.hung.compactMap { id in session.notes.first { $0.id == id } }
  }

  private var delivery: Int { store.state.pet.world.delivery }

  private var isRenovating: Bool { session.renovator.isRenovating }

  /// Long enough to see the note set off before the system prompt covers it.
  private static let askAfterSending = Duration.seconds(2)

  var body: some View {
    home
      .environment(\.petSceneCat, session.labs.cat)
      .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: session.play.petsGiven)
      .sensoryFeedback(.success, trigger: session.treatFalling) { _, falling in falling }
      .modifier(
        HomeShop(
          shop: session.shop, renovator: session.renovator, scene: scene,
          showsButtons: !variant.isFullBleed, sheet: $shopSheet)
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
      .task(id: line) {
        withAnimation(Motion.spring) { showsStatus = true }
        guard line.settles else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.spring) { showsStatus = false }
      }
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
          .navigationTransition(.zoom(sourceID: Self.drawButton, in: zoom))
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

  /// The chosen room style when the scene can show it and Home has room for the floating
  /// controls; `nil` keeps the classic layout.
  private var roomStyle: RoomStyle? {
    let style = session.labs.roomStyle
    guard style != .nooki, !typeSize.isAccessibilitySize, !isRenovating,
      scene?.roomStyles.contains(style) == true
    else { return nil }
    return style
  }

  /// How Home is laid out. Large text and renovating keep the classic layout, which has room for
  /// both.
  private var variant: HomeVariant {
    guard scene != nil, !typeSize.isAccessibilitySize, !isRenovating else { return .classic }
    return session.labs.homeVariant
  }

  /// The chosen room style when the scene can show it, else the scene's own room.
  private var sceneRoomStyle: RoomStyle {
    let style = session.labs.roomStyle
    return scene?.roomStyles.contains(style) == true ? style : .standard
  }

  private var latestReceivedNote: NoteRecord? {
    session.notes.first { $0.direction == .received }
  }

  @ViewBuilder private var home: some View {
    if variant.isFullBleed, let scene {
      fullBleedHome(scene)
        .overlay { nightOverlay }
        .overlay(alignment: .top) {
          if !line.settles { roomStatus }
        }
    } else if let roomStyle, let scene {
      styledHome(roomStyle, scene: scene)
        .overlay { nightOverlay }
        .overlay(alignment: .top) {
          if !line.settles { roomStatus }
        }
    } else {
      classicHome
    }
  }

  private func styledHome(_ style: RoomStyle, scene: any PetScene) -> some View {
    let calendar = Calendar.current
    let today = TreatDay.key(for: .now, calendar: calendar)
    return StyledHome(
      style: style,
      scene: AnyView(
        scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
          .id(scene.id)
          .environment(\.petSceneOnScreen, store.state.screen == .home)
          .environment(\.petSceneRenovator, session.renovator)
          .overlay { catReactions.allowsHitTesting(false) }),
      notes: session.notes,
      streak: session.streak(today: today, calendar: calendar),
      treats: ShopCatalog.standard.items(in: .treats).reduce(0) { $0 + session.shop.owned($1) },
      isFakePartner: session.isFakePartner,
      onChooseStyle: { session.labs.setRoomStyle($0) },
      onTreat: { giveTreat(on: today) },
      onOpenNotes: onOpenNotes,
      onDraw: { store.send(.canvasOpened) })
  }

  private func fullBleedHome(_ scene: any PetScene) -> some View {
    let style = sceneRoomStyle
    return FullBleedHome(
      variant: variant,
      scene: AnyView(
        scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
          .id(scene.id)
          .environment(\.petSceneOnScreen, store.state.screen == .home)
          .environment(\.petSceneRenovator, session.renovator)
          .environment(\.petSceneRoomStyle, style)
          .environment(\.petSceneDrawing, style == .nooki ? hungImage : latestDrawing)
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
          .background {
            // The styled rooms draw their own night; the diorama floats in Home's evening, or
            // under the sky of the hour when Home follows the time of day.
            if style == .nooki {
              if variant == .nightAndDay { skyBackdrop } else { homeBackdrop }
            }
          }),
      director: director,
      isFakePartner: session.isFakePartner,
      theirTimeZone: session.lamp.theirs?.timeZoneID.flatMap(TimeZone.init(identifier:)),
      hasOpened: hasOpened,
      onOpened: { hasOpened = true },
      onTreat: { giveTreat(on: TreatDay.key(for: .now, calendar: .current)) },
      onDraw: { store.send(.canvasOpened) },
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
      HStack(spacing: Spacing.small) {
        Label("\(streak) \(streak == 1 ? "day" : "days")", systemImage: "flame.fill")
          .billetType(.action)
          .foregroundStyle(Palette.paper.color)
          .accessibilityIdentifier("drawerStreak")
        Spacer(minLength: 0)
        if scene.hasShop {
          IconButton("paintbrush.pointed", label: "Change the room") {
            drawerOpen = false
            session.renovator.requestOpen()
          }
          IconButton("archivebox.fill", label: "Closet") { openShop(.closet) }
          IconButton("bag.fill", label: "Shop") { openShop(.shop) }
        }
      }
      controls(showsDraw: false)
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

  /// The sky of the hour here, from the same colours as the partner's sky card.
  private var skyBackdrop: some View {
    TimelineView(.everyMinute) { context in
      let colours = TheirSky.at(hour: Calendar.current.component(.hour, from: context.date))
        .colours
      LinearGradient(
        colors: [colours.top.color, colours.bottom.color], startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()
    }
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
    .overlay(alignment: .top) { roomStatus }
  }

  /// Dark over the scene while both lamps are out.
  @ViewBuilder private var nightOverlay: some View {
    if session.labs.isOn(LabExperiment.lightsOut) {
      TimelineView(.everyMinute) { context in
        NightOverlay(night: session.lamp.night(at: context.date))
      }
    }
  }

  @ViewBuilder private var framedWall: some View {
    if session.labs.isOn(LabExperiment.framedNotes) {
      FramedWallView(notes: framedNotes)
    }
  }

  @ViewBuilder private var petScene: some View {
    if let scene {
      scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
        .id(scene.id)
        .environment(\.petSceneOnScreen, store.state.screen == .home)
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
          // A scene with touches keeps its own controls in the corners the season would fill.
          if session.labs.isOn(LabExperiment.seasons), !scene.handlesTouches {
            SeasonOverlay(look: Season.look(on: .now, calendar: .current))
          }
        }
        .overlay(alignment: .topLeading) {
          if !scene.handlesTouches { framedWall }
        }
        .background(alignment: .topLeading) {
          // A scene with touches keeps its controls in this corner, drawn over the frames.
          if scene.handlesTouches { framedWall.padding(.top, Spacing.wide) }
        }
        .overlay(alignment: .bottomLeading) {
          if catAway {
            OvernightStayView()
              .scaleEffect(0.55, anchor: .bottomLeading)
              .padding(.leading, Spacing.small)
              .padding(.bottom, Spacing.small)
          }
        }
        .overlay {
          if let hungImage, let wall = scene.noteWall {
            HungNote(drawing: hungImage, wall: wall)
              .id(hangCount)
          }
        }
    }
  }

  private var controls: some View { controls(showsDraw: true) }

  private func controls(showsDraw: Bool) -> some View {
    VStack(spacing: Spacing.small) {
      if session.notes.isEmpty, !session.notesFailedToLoad {
        Text("The wall is empty. Draw the first note.")
          .billetType(.label)
          .foregroundStyle(Palette.paperTurned.color)
          .multilineTextAlignment(.center)
          .transition(.opacity)
      }
      if typeSize.isAccessibilitySize { fakePartnerNotice }
      overnightStayNotice
      catCameBackNotice
      catNaming
      latestReceived
      treatPanel
      promptCards
      if LabExperiment.allCases.contains(where: { $0.hasHomeCard && session.labs.isOn($0) }) {
        labsDrawer
      }
      if showsDraw {
        BilletButton("Draw a note", rank: .primary) { store.send(.canvasOpened) }
          .matchedTransitionSourceIfAvailable(id: Self.drawButton, in: zoom)
      }
    }
    .calmAnimation(value: session.notes.isEmpty)
    .calmAnimation(value: session.play.catName)
    .calmAnimation(value: catAway)
  }

  /// A TimelineView lets the satchel go away on its own once its twelve hours are up.
  @ViewBuilder private var catCameBackNotice: some View {
    if session.labs.isOn(LabExperiment.catCameBack) {
      TimelineView(.everyMinute) { context in
        if session.catReturn.isBack(now: context.date) {
          CatCameBackRow(catName: session.play.catName)
            .transition(.opacity)
        }
      }
    }
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
            twoWispsCard
            lampColourCard
            theirSkyCard
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

  @ViewBuilder private var theirSkyCard: some View {
    if session.labs.isOn(LabExperiment.theirSky) {
      TheirSkySection(store: session.lamp)
    }
  }

  @ViewBuilder private var porchLightCard: some View {
    if session.labs.isOn(LabExperiment.porchLight) {
      PorchLightSection(store: session.porch)
    }
  }

  @ViewBuilder private var twoWispsCard: some View {
    if session.labs.isOn(LabExperiment.twoWisps) {
      TwoWispsSection(hold: session.hold, catName: session.play.catName) {
        session.holdChanged($0)
      }
    }
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

  @ViewBuilder private var overnightStayNotice: some View {
    if catAway {
      let name = session.play.catName
      ListRow(
        OvernightStayCaption.title(catName: name),
        subtitle: OvernightStayCaption.detail(catName: name)
      ) {
        EmptyView()
      } trailing: {
        EmptyView()
      }
      .card()
      .transition(.opacity)
      .accessibilityIdentifier("overnightStayNotice")
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
    case .noteOpened: onOpenNotes()
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
      catAway: catAway
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

  @ViewBuilder private var roomStatus: some View {
    if showsStatus {
      VStack(spacing: Spacing.small) {
        statusPill
        if line == .refused {
          BilletButton("Change code", rank: .secondary, action: onChangeCode)
            .frame(maxWidth: 200)
        }
      }
      .padding(.top, Spacing.small)
      .padding(.horizontal, Spacing.medium)
      .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      .transition(.opacity)
    }
  }

  /// A scene with its own buttons leaves room between them for the short line only.
  private var hasRoomControls: Bool { scene?.handlesTouches == true }

  private var statusPill: some View {
    HStack(spacing: Spacing.small) {
      Circle()
        .fill(statusLight.color)
        .frame(width: Spacing.small, height: Spacing.small)
        .accessibilityHidden(true)
      Text(session.isFakePartner && !hasRoomControls ? "Fake partner · \(line.text)" : line.text)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
    }
    .calmAnimation(value: line)
    .padding(.horizontal, Spacing.medium)
    .frame(minHeight: Target.minimum)
    .floatingGlass()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("connectionStatus")
  }

  private var statusLight: Swatch {
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

extension View {
  fileprivate func matchedTransitionSourceIfAvailable(
    id: String, in namespace: Namespace.ID
  ) -> some View {
    #if os(iOS)
      matchedTransitionSource(id: id, in: namespace)
    #else
      self
    #endif
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

/// What the streak is worked out from, so it is worked out again when either changes.
private struct StreakInputs: Equatable {
  let ledger: TreatLedger
  let porch: PorchLight?
}
