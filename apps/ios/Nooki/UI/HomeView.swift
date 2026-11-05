import FeatureGames
import SwiftUI
import TipKit
import Transport
import WidgetBridge
import Wire

struct HomeView: View {
    /// Owned by NookiApp: a `@State` default here would read every store again on each pass of the app's `body`.
    @Binding var state: HomeState
    /// Built after the first frame, so launch shows the backdrop at once.
    @State private var home: DioramaScene?
    /// Built each time the City room is opened, released when it is left.
    @State private var city: CityRoomScene?
    /// The corkboard room behind the Moments tab, built on first use and kept.
    @State private var board: BoardRoomScene?
    @State private var showcase: String?
    @State private var petSentAt: Date = .distantPast
    /// The splash stays over everything until the room has loaded (see `lift()`).
    @State private var launching = true
    /// The screen as the World last showed it, held up on the way back until the room draws again.
    @State private var worldSnapshot: UIView?
    /// Whether the room has drawn since the World came back; until then `worldSnapshot` stands in for it.
    @State private var roomLive = true
    /// The Coins sheet's packs, once there is a server to buy them through.
    @State private var coinPacks: CoinPacksModel?
    /// The Coins sheet on screen, a moment after the shop asked for it.
    @State private var coinsShown: CoinsAsk?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Hints.self) private var hints
    @Environment(ServerSession.self) private var session: ServerSession?
    @AppStorage(AppSettings.brainCardKey) private var brainCard = false
    /// Whether this pair has both rooms to switch between.
    private var hasRoomChoice: Bool { state.rooms.variant.hasRoomChoice }
    /// The rooms already counted as opened since the app came to the front, so each is reported once.
    @State private var reportedRooms: Set<RoomKind> = []

    /// The board room behind the Moments tab, when it shows the board rather than the feed.
    private var showsBoard: Bool { state.tab == .moments && state.momentsMode == .board }
    /// The World tab and the board show a room; the others get their own screens over the backdrop.
    private var showsRoom: Bool { state.tab == .world || showsBoard }
    /// Something hides the room whole: the canvas, the Inbox or the composer over it, or the app not in front.
    private var roomCovered: Bool {
        state.drawing || state.showsInbox || state.composingNote != nil || scenePhase != .active
    }
    /// The room is mounted only while it can be seen.
    private var roomOnScreen: Bool { showsRoom && !roomCovered }
    /// The World's room can be seen; when it can't, its last frame is kept to show on the way back.
    private var worldOnScreen: Bool { state.tab == .world && !roomCovered }

    var body: some View {
        ZStack {
            // The bokeh drifts only around a room: under the Shop, Moments and Us it holds still, so their scrolling
            // and the glass over them never redraw a moving backdrop every frame.
            WarmBackdrop(drifts: roomOnScreen)

            // The City window's view, seen through the hole in the room's wall; never takes a touch.
            if !Self.noRoom, showsRoom, !showsBoard, state.room == .city, let city {
                CityWindowLayer(view: city.windowView)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .ignoresSafeArea()
            }

            if Self.noRoom {
                // A stand-in for the room under the UI tests, which cannot draw RealityKit on CI's virtual Macs.
                Color.clear
                    .contentShape(.rect)
                    .allowsHitTesting(showsRoom)
                    .modifier(RoomTapCounter())
                    .ignoresSafeArea()
            } else if let scene, roomOnScreen {
                // Only while a room can be seen: a paused RealityView left in place under the Shop, Moments, Us or a
                // cover still runs its render loop and composites a full-screen layer every frame. The room itself
                // stays loaded (CatRoom), so coming back only makes a new view for it.
                DioramaView(scene: scene, paused: !showsRoom, petPulse: state.care.petPulse) {
                    withAnimation(.spring(duration: 0.4)) { state.care.pet() }
                }
                .opacity(showsRoom ? 1 : 0)
                .allowsHitTesting(showsRoom && state.game == nil)
                .modifier(RoomTapCounter())
                .ignoresSafeArea()
            }

            // A new RealityView takes a moment to draw its first frame; the last one shows meanwhile.
            if state.tab == .world, !roomLive || roomCovered, let worldSnapshot {
                SnapshotView(view: worldSnapshot)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            Group {
                switch state.tab {
                case .shop:
                    ShopView(state: state)
                case .moments:
                    MomentsView(state: state)
                case .us:
                    UsView(state: state)
                case .world:
                    VStack(spacing: 16) {
                        RoomControls(state: state, select: select)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 12)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The same header, in the same place, on every tab, and the tab bar: bars over the tab, so its scroll
            // view runs full-bleed under both and only its content is inset.
            .bars(fades: !showsRoom) {
                AppHeader(state: state) {
                    scene?.stop()
                    HomeState.eraseAll()
                    state = HomeState(stores: .live())
                    Task { await followPair() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            } bottom: {
                TabBar(state: state)
                    .padding(.horizontal, 16)
            }
            .opacity(state.game == nil ? 1 : 0)

            if let game = state.game, let scene {
                // In the room, with nothing else of Home over it.
                GameView(session: GameSession(game: game, room: scene, catEvents: session?.catEvents ?? .offline)) {
                    state.game = nil
                }
                .id(game)
                .transition(.opacity)
            }

            // The composer and the canvas play it over themselves while they're up.
            if state.composingNote == nil, !state.drawing { PurchaseMoment(state: state) }
        }
        // Above the tab bar, so both stay clear of the "+" in the right corner.
        .overlay(alignment: .bottom) {
            if state.tab == .world, state.game == nil {
                HStack(alignment: .bottom) {
                    PetButton(state: state, needs: { scene?.director }) { game in state.game = game }
                    Spacer(minLength: 0)
                    PlayAllButton(showcase: showcase) { scene?.playAll() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 94)
                .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .overlay(alignment: .topLeading) {
            if brainCard && state.tab == .world {
                // The brain starts once Mochi has loaded, after this view has drawn; look again now and then.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let director = scene?.director { BrainCard(director: director) }
                }
                .padding(.leading, 16)
                .padding(.top, 120)
            }
        }
        // Covered by the splash, Home is not there for VoiceOver or UI tests either: a tap aimed at a control under
        // the splash would land on the splash.
        .accessibilityHidden(launching)
        // Over the room rather than in place of it: RealityKit keeps drawing underneath, so the room is already
        // warmed up and whole when the splash lifts.
        .overlay {
            if launching {
                // A removed view keeps its last state while it fades, so the splash never takes taps itself; the
                // stand-in below does, and goes the moment the splash starts to lift.
                LaunchSplash()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Nooki is opening")
                    .accessibilityIdentifier("launch-splash")
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                Color.clear
                    .contentShape(.rect)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .transition(.identity)
            }
        }
        .task {
            NookiPerf.start(state: state)
            await lift()
        }
        .task {
            guard home == nil, !Self.noRoom else { return }
            home = DioramaScene()
        }
        // Nil until the room exists, so the photos are printed once it does and again only when the pins change.
        .task(id: wallPins) {
            guard let home else { return }
            let images = await state.moments.filmPrints(for: state.moments.pinned, maxPixels: MomentStore.wallPixels)
            if !Task.isCancelled { home.setPolaroids(images) }
        }
        .task(id: boardKey) {
            guard board != nil else { return }
            let pins = await BoardFaces.pins(state: state)
            if !Task.isCancelled { board?.setPins(pins) }
        }
        .onChange(of: showsBoard) { old, new in
            // DioramaView swaps the root by itself; stop the room that was showing so two never drive at once.
            let previous: CatRoom? = old ? board : (state.room == .city ? city ?? home : home)
            previous?.stop()
            if new, board == nil { board = makeBoard() }
        }
        .onChange(of: state.room) {
            showcase = nil
            reportOpened(state.room)
        }
        // A variant with one room never leaves Home on a room it lacks.
        .onChange(of: state.rooms.variant) { _, variant in
            if !variant.kinds.contains(state.room) { select(variant.kinds[0]) }
        }
        .onChange(of: worldOnScreen) { old, new in
            // The room view goes when the World can't be seen (see above): keep what it showed, to show again on the
            // way back and under a cover. Not while something is presented, a hint's popover say: the snapshot would
            // bring it back with the room.
            if old, !new, !(showsBoard && !roomCovered) {
                worldSnapshot =
                    Hints.keyWindowIsPresenting() ? nil : Self.keyWindow?.snapshotView(afterScreenUpdates: false)
            }
            if new, let scene, worldSnapshot != nil {
                roomLive = false
                let start = scene.frame
                Task {
                    let deadline = ContinuousClock.now + .seconds(2)
                    while scene.frame == start, ContinuousClock.now < deadline {
                        try? await Task.sleep(for: .milliseconds(8))
                    }
                    withAnimation(.easeOut(duration: 0.2)) { roomLive = true }
                    try? await Task.sleep(for: .milliseconds(250))
                    if roomLive { worldSnapshot = nil }
                }
            }
        }
        .onChange(of: state.tab) { _, tab in
            NookiPerf.tabShown(tab)
            if tab == .world, let scene { NookiPerf.shown(scene, kind: state.room) }
        }
        // Pets from the widget and the control reach Mochi when the app comes back.
        .onChange(of: state.care.petPulse) {
            scene?.purr()
            hints.done(PetHint())
        }
        .onChange(of: state.care.treatsGiven) { hints.done(TreatHint()) }
        // A run of pets is one in the pair's journal and Inbox: one every 10 minutes at most.
        .onChange(of: state.care.petsGiven) {
            guard let session, Date.now.timeIntervalSince(petSentAt) > 600 else { return }
            petSentAt = .now
            Task { await session.catEvents.send([.petted]) }
        }
        .onChange(of: state.tab, initial: true) { visitHints() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                state.refresh()
                scene?.appOpened()
                visitHints()
                Task {
                    await DrawingSync.requestPushes(asking: false)
                    await session?.drawingSync?.fetchLatest()
                    await session?.drawingSync?.registerPushTokens()
                    await session?.inbox.refreshCount()
                    await photoSync?.receive()
                    await textSync?.receive()
                    await state.shop.refresh()
                }
                session?.reactions?.refresh()
                session?.followInbox(true, photos: photoSync, texts: textSync, shop: state.shop)
                refreshRooms()
                if !launching { reportOpened(state.room) }
            case .background:
                state.didEnterBackground()
                session?.followInbox(false)
                reportedRooms = []
            default: break
            }
        }
        .sheet(item: $state.composingNote) { mode in
            NoteComposer(state: state, mode: mode)
        }
        .sheet(isPresented: $state.showsInbox) {
            if let inbox = session?.inbox {
                InboxView(model: inbox, state: state) { target in
                    withAnimation(.spring(duration: 0.4)) { state.open(target) }
                }
                .presentationDetents([.large])
                .presentationBackground(Ink.sheet)
                .presentationDragIndicator(.visible)
            } else {
                InboxSignedOut(petName: state.petName)
                    .presentationBackground(Ink.sheet)
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: state.shop.coinsAsk) { _, ask in
            guard let ask else { return coinsShown = nil }
            Task {
                // A short buy comes from a sheet that closes first: the Coins sheet waits for it to go.
                if ask.missing > 0 { try? await Task.sleep(for: .milliseconds(450)) }
                coinsShown = ask
            }
        }
        .sheet(item: $coinsShown, onDismiss: { state.shop.coinsAsk = nil }) { ask in
            CoinsSheet(state: state, packs: coinPacks, ask: ask)
        }
        .sheet(item: $state.openedShopItem) { item in
            ItemSheet(item: item, state: state)
        }
        .fullScreenCover(isPresented: $state.drawing) {
            LockCanvasView(
                state: state, api: session?.api,
                model: DrawModel(room: session?.liveRoom(), partnerName: state.otherPartner))
        }
        .task { await DrawingSync.watchLiveActivities() }
        .task {
            guard coinPacks == nil, let payments = session?.payments else { return }
            let shop = state.shop
            coinPacks = CoinPacksModel(payments: payments) {
                await shop.refresh()
                await shop.loadHistory()
            }
        }
        .task(id: session?.isPaired) { await followPair() }
        // A new photo, or one that failed to go earlier, goes to the partner.
        .task(id: state.moments.unsent.map(\.id)) { await photoSync?.sendUnsent() }
        .task(id: state.notes.unsent.map(\.id)) { await textSync?.sendUnsent() }
        .onReceive(NotificationCenter.default.publisher(for: .pushTokenChanged)) { _ in
            Task { await session?.drawingSync?.registerPushTokens() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .coupleChanged)) { _ in state.profile.reload() }
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            withAnimation(.spring(duration: 0.4)) { state.open(link) }
        }
    }

    /// Lifts the splash once the room is ready, never sooner than its own little intro and never later than 6 s.
    private func lift() async {
        let start = Date()
        while launching {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 6 || elapsed > 1.6 && home?.isReady == true { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // A few frames for the last loaded pieces to draw.
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: 0.8)) { launching = false }
        // `-room city` on launch opens the City room, for recordings and screenshots.
        if UserDefaults.standard.string(forKey: "room") == "city" || state.rooms.variant.firstRoom == .city {
            select(.city)
        } else if let home {
            NookiPerf.shown(home, kind: .home)
        }
        #if DEBUG
        // `-tab shop` opens the Shop, for screenshots.
        if UserDefaults.standard.string(forKey: "tab") == "shop" { state.tab = .shop }
        #endif
        reportOpened(state.room)
    }

    /// Reads the pair's variants while the account has a partner, and forgets them when it has none.
    private func refreshRooms() {
        guard let session else { return }
        guard session.isPaired else { return state.rooms.forget() }
        let rooms = state.rooms
        Task { await rooms.refresh(session.api) }
    }

    /// Counts `RoomOpened` once per room each time the app is in front, so the test can compare the rooms.
    private func reportOpened(_ room: RoomKind) {
        guard let session, state.tab == .world, reportedRooms.insert(room).inserted else { return }
        let api = session.api
        Task { try? await api.reportEvents([ClientEvent(.roomOpened, detail: room.eventDetail)]) }
    }

    private func select(_ room: RoomKind) {
        guard room != state.room else { return }
        if room == .city { hints.done(RoomsHint()) }
        if room == .city {
            // Building the City holds the main thread for a moment, so it waits for the switch to finish moving;
            // until then the home room stays on screen and running, and a tap back to it just stays there.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard state.room == .city, city == nil else { return }
                home?.stop()
                let built = CityRoomScene()
                city = built
                NookiPerf.shown(built, kind: .city)
            }
        } else {
            city?.stop()
            city = nil
            if let home { NookiPerf.shown(home, kind: .home) }
        }
        withAnimation(.snappy(duration: 0.25)) { state.room = room }
    }

    /// `-uitestNoRoom YES` leaves the room out (see the stand-in in `body`).
    private static let noRoom = UserDefaults.standard.bool(forKey: "uitestNoRoom")

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    private var scene: CatRoom? {
        guard let home else { return nil }
        if showsBoard, let board { return board }
        let room: CatRoom = state.room == .city ? city ?? home : home
        room.onShowcase = { label in withAnimation(.snappy(duration: 0.25)) { showcase = label } }
        return room
    }

    /// The moments on the room's wall, nil until the room exists.
    private var wallPins: [Moment]? { home == nil ? nil : state.moments.pinned }

    /// The ids of the newest notes on the board; a new set rebuilds their faces.
    private var boardKey: [String] { BoardFaces.key(state: state) }

    /// Photos to and from the partner; nil until this phone is paired with them.
    /// Once paired, the monograms belong to the pair's two accounts and the shop and the gifts follow the pair's room.
    private func followPair() async {
        #if DEBUG
        if ShopFixture.isOn { return await state.shop.connect(ShopFixture(offers: state.shop.offers).sync) }
        #endif
        guard let session, let sync = session.shopSync else { return await leavePair() }
        do throws(TransportError) {
            let pair = try await session.pair()
            state.profile.adopt(
                pairID: pair.pairId.rawValue, me: pair.members[0].rawValue, partner: pair.members[1].rawValue)
        } catch {
            if error == .api(.notFound) { return await leavePair() }
            // Offline: a phone that already took the pair keeps following it.
            guard state.profile.couple.pair != nil else { return }
        }
        await state.shop.connect(sync)
        await state.gifts.connect(session.giftSync)
    }

    private func leavePair() async {
        state.profile.leavePair()
        await state.shop.connect(nil)
        await state.gifts.connect(nil)
    }

    /// Each tab shown, and each return to the app, is a visit that may show one hint.
    private func visitHints() {
        hints.visit {
            let screen: HintScreen = switch state.tab {
            case .world: .world
            case .moments: .moments
            case .shop: .shop
            case .us: .other
            }
            let sheet = state.composingNote != nil || state.drawing || state.showsProfile || state.showsInbox
                || state.openedShopItem != nil
            let buying = state.shop.lastPurchase?.canUndo(at: .now) == true
            return HintContext(
                screen: screen, busy: sheet || buying || showcase != nil, hasRoomChoice: hasRoomChoice,
                canAffordTreat: state.shop.coins >= ShopModel.treatPrice)
        }
    }

    /// Photos to and from the partner; nil until this phone is paired with them.
    private var photoSync: PhotoSync? {
        session?.photoSync(moments: state.moments, partner: state.otherPartner)
    }

    private var textSync: TextNoteSync? {
        session?.textSync(notes: state.notes, partner: state.otherPartner)
    }

    /// Builds the corkboard room and draws its first cards, so the tab opens with the board already pinned.
    private func makeBoard() -> BoardRoomScene {
        let room = BoardRoomScene()
        let state = self.state
        room.onOpen = { state.openedPin = PinRoute(id: $0) }
        room.onDraw = { state.composingNote = .draw }
        Task {
            let pins = await BoardFaces.pins(state: state)
            room.setPins(pins)
        }
        return room
    }
}

/// Switches between Mochi's rooms.
private struct RoomControls: View {
    let state: HomeState
    var select: (RoomKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            // One room has no switch: its name would be the only choice.
            if state.rooms.variant.hasRoomChoice {
                roomSwitch
            }

            Spacer(minLength: 0)
        }
    }

    private var roomSwitch: some View {
        HStack(spacing: 2) {
            ForEach(state.rooms.variant.kinds, id: \.self) { room in
                Button { select(room) } label: {
                    Text(room.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(state.room == room ? 0.96 : 0.6))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(state.room == room ? Color.honey.opacity(0.45) : .clear, in: .capsule)
                        // 44 pt tall to the finger, though 34 to the eye; a miss would land on the room.
                        .frame(height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(state.room == room ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background { Color.clear.warmGlass(.capsule).padding(.vertical, 2) }
        .sensoryFeedback(.selection, trigger: state.room)
        .popoverTip(RoomsHint(), arrowEdge: .top)
    }
}

/// Plays all Mochi's animations in turn, naming each as it plays.
private struct PlayAllButton: View {
    let showcase: String?
    var playAll: () -> Void

    var body: some View {
        Button(action: playAll) {
            HStack(spacing: 6) {
                Image(systemName: showcase == nil ? "play.fill" : "sparkles")
                Text(showcase ?? "Play all")
                    .contentTransition(.opacity)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 40)
            // Not interactive: the button style answers the press; interactive glass would track the same touch.
            .warmGlass(.capsule)
            .frame(height: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(showcase != nil)
        .accessibilityLabel(showcase.map { "Playing \($0)" } ?? "Play all animations")
    }
}

/// A snapshot from `UIView.snapshotView(afterScreenUpdates:)`, filling the view it is put in.
private struct SnapshotView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.isUserInteractionEnabled = false
        view.frame = holder.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
        return holder
    }

    func updateUIView(_ holder: UIView, context: Context) {}
}

/// Dark amber vignette with drifting bokeh, standing in for the depth-of-field blur of the reference.
private struct WarmBackdrop: View {
    /// Whether the bokeh moves; when it doesn't, it stays where it was.
    var drifts = true
    @Environment(\.scenePhase) private var scenePhase
    /// `-uitestStill YES` holds the bokeh still: redrawn under glass every frame, it keeps the app from ever idling
    /// on CI's GPU-less virtual Macs, and UI queries time out.
    private static let still = UserDefaults.standard.bool(forKey: "uitestStill")
    private var paused: Bool { scenePhase != .active || !drifts || Self.still }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0xF4BF7E), Color(hex: 0xB36E3A), Color(hex: 0x4A2C1B), Color(hex: 0x24150D)],
                center: UnitPoint(x: 0.5, y: 0.48),
                startRadius: 10,
                endRadius: 520
            )
            // 10 Hz: the drift is at most 18–24 pt over half a minute, a fraction of a pixel a step, and each step
            // redraws the full screen under the room and its glass.
            TimelineView(.animation(minimumInterval: 1 / 10, paused: paused)) { context in
                Canvas { ctx, size in
                    let t = context.date.timeIntervalSinceReferenceDate
                    for i in 0..<14 {
                        let seed = Double(i) * 12.9898
                        let x = (sin(seed) * 0.5 + 0.5) * size.width + sin(t * 0.15 + seed) * 18
                        let y = (cos(seed * 1.7) * 0.5 + 0.5) * size.height + cos(t * 0.12 + seed) * 24
                        let r = 6 + (sin(seed * 3.1) * 0.5 + 0.5) * 16
                        let alpha = 0.18 + 0.14 * sin(t * 0.6 + seed)
                        // A soft edge `soft` wide on either side of the rim, in place of blurring the whole canvas.
                        let soft = 6.0, outer = r + soft
                        let dot = Gradient(stops: [
                            .init(color: Color(hex: 0xFFD79A, opacity: alpha), location: max(0, r - soft) / outer),
                            .init(color: Color(hex: 0xFFD79A, opacity: 0), location: 1),
                        ])
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - outer, y: y - outer, width: outer * 2, height: outer * 2)),
                            with: .radialGradient(dot, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: outer)
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Under the UI tests (`-uitestRoomTaps YES`), counts every tap that reaches the room and reports it as the room's
/// accessibility value, so a test can tell that a tap on the tab bar never fell through. Off otherwise.
private struct RoomTapCounter: ViewModifier {
    @State private var taps = 0
    private let counts = UserDefaults.standard.bool(forKey: "uitestRoomTaps")

    func body(content: Content) -> some View {
        if counts {
            content
                .simultaneousGesture(TapGesture().onEnded { taps += 1 })
                .accessibilityElement()
                .accessibilityIdentifier("room")
                .accessibilityValue("\(taps)")
        } else {
            content
        }
    }
}

private extension View {
    /// The header and the tab bar as the screen's top and bottom bars. On iOS 26 they are safe area bars with the
    /// soft scroll edge under them; before, safe area insets over a material fade when `fades`.
    @ViewBuilder
    func bars(fades: Bool, @ViewBuilder top: () -> some View, @ViewBuilder bottom: () -> some View) -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .vertical)
                .safeAreaBar(edge: .top, spacing: 12, content: top)
                .safeAreaBar(edge: .bottom, content: bottom)
        } else {
            safeAreaInset(edge: .top, spacing: 12) {
                top().background { if fades { EdgeFade(edge: .top) } }
            }
            .safeAreaInset(edge: .bottom) {
                bottom().background { if fades { EdgeFade(edge: .bottom) } }
            }
        }
    }
}

/// Below iOS 26: material that fades out away from the screen edge, under a bar and through the status bar or the
/// home indicator, so scrolled content softens instead of ending at a line.
private struct EdgeFade: View {
    let edge: VerticalEdge

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(LinearGradient(colors: [.black, .black, .clear],
                                 startPoint: edge == .top ? .top : .bottom,
                                 endPoint: edge == .top ? .bottom : .top))
            .padding(edge == .top ? .bottom : .top, -20)
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
            .allowsHitTesting(false)
    }
}
