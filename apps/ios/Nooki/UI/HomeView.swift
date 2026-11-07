import FeatureGames
import SwiftUI
import Design
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
    @State var showcase: String?
    /// A bare room for the games under `-uitestNoRoom`, where no real one is built.
    @State private var standInRoom = CatRoom()
    @State private var petSentAt: Date = .distantPast
    /// The splash stays over everything until the room has loaded (see `lift()`).
    @State private var launching = true
    /// The splash is still drawn while it fades out after `launching` ends, though it takes no touches by then.
    @State private var splashDrawn = true
    /// The screen as the World last showed it, held up on the way back until the room draws again.
    @State private var worldSnapshot: UIView?
    /// Whether the room has drawn since the World came back; until then `worldSnapshot` stands in for it.
    @State private var roomLive = true
    /// A room switch is under way; another waits for it.
    @State private var switchingRoom = false
    /// The Coins sheet's packs, once there is a server to buy them through.
    @State private var coinPacks: CoinPacksModel?
    /// The Coins sheet on screen, a moment after the shop asked for it.
    @State private var coinsShown: CoinsAsk?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Hints.self) var hints
    @Environment(ServerSession.self) var session: ServerSession?
    @AppStorage(AppSettings.brainCardKey) private var brainCard = false
    /// Whether this pair has both rooms to switch between.
    var hasRoomChoice: Bool { state.rooms.variant.hasRoomChoice }
    @State private var height: CGFloat = 0
    /// The rooms already counted as opened since the app came to the front, so each is reported once.
    @State var reportedRooms: Set<RoomKind> = []

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
                        RoomSwitch(state: state, select: select)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }
            }
            // A short crossfade between tabs; the header and the tab bar are outside it and stay put.
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: state.tab)
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

            if let game = state.game, let room = scene ?? (Self.noRoom ? standInRoom : nil) {
                // In the room, with nothing else of Home over it.
                GameView(session: GameSession(game: game, room: room, catEvents: session?.catEvents ?? .offline)) {
                    state.game = nil
                }
                .id(game)
                .transition(.opacity)
            }

            // The composer and the canvas play it over themselves while they're up.
            if state.composingNote == nil, !state.drawing { PurchaseMoment(state: state) }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        // Above the tab bar, so both stay clear of the "+" in the right corner.
        .overlay(alignment: .bottom) {
            if state.tab == .world, state.game == nil {
                VStack(alignment: .leading, spacing: 12) {
                    // Above the portrait, with the arrow down at it, so the hint never covers her.
                    TipView(PetHint(), arrowEdge: .bottom)
                    TipView(TreatHint(), arrowEdge: .bottom)
                    HStack(alignment: .bottom) {
                        PetButton(state: state, needs: { scene?.director }) { game in state.game = game }
                        Spacer(minLength: 0)
                        if let showcase { ShowcaseLabel(label: showcase) }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 94)
                .transition(.opacity)
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
            // Faded by state, not by a removal transition: a view on its way out keeps its last state, so it would
            // still take touches and still be in the accessibility tree through the fade.
            if splashDrawn {
                LaunchSplash()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Nooki is opening")
                    .accessibilityIdentifier("launch-splash")
                    .opacity(launching ? 1 : 0)
                    .scaleEffect(launching ? 1 : 1.08)
                    .allowsHitTesting(launching)
                    .accessibilityHidden(!launching)
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
        // Settings › Labs asks for the showcase, once it is closed.
        .onChange(of: state.showcaseRequested) { _, requested in
            guard requested else { return }
            state.showcaseRequested = false
            scene?.playAll()
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
        .task { hints.isHeldOut = { [rooms = state.rooms] in rooms.remote.variant(of: Experiments.hints) == HintHoldout.hold } }
        .onChange(of: scenePhase, initial: true) { old, phase in
            switch phase {
            case .active:
                // The first call is launch, where every store has just been read.
                state.refresh(reloading: old != phase)
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
                    await state.lists.refresh()
                }
                // The room socket sends no game frames it missed while the app was away. Its own task, so missed
                // photos downloading above don't hold it up.
                Task { await session?.whoKnows.load() }
                session?.reactions?.refresh()
                session?.followInbox(
                    true, photos: photoSync, texts: textSync, shop: state.shop, lists: state.lists,
                    moods: { [state] in state.moodSync?.received($0) })
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
            } else {
                InboxSignedOut(petName: state.petName)
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
                model: DrawModel(room: session?.liveRoom(), partnerName: state.otherPartner), coinPacks: coinPacks)
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
        withAnimation(.easeInOut(duration: 0.8)) { launching = false } completion: { splashDrawn = false }
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

    /// Visits another room with one crossfade: the screen as it is stands in over the swap, and fades out once the
    /// new room has drawn. The City is built under the stand-in, which hides the moment it holds the main thread.
    private func select(_ room: RoomKind) {
        guard room != state.room, !switchingRoom else { return }
        if room == .city { hints.done(RoomsHint()) }
        switchingRoom = true
        worldSnapshot = Hints.keyWindowIsPresenting() ? nil : Self.keyWindow?.snapshotView(afterScreenUpdates: false)
        var still = Transaction(animation: nil)
        still.disablesAnimations = true
        withTransaction(still) { roomLive = false }
        // The switch moves at once; the room under the stand-in follows it.
        withAnimation(.snappy(duration: 0.25)) { state.room = room }
        Task {
            // One pass for the stand-in to be on screen before the room under it changes.
            try? await Task.sleep(for: .milliseconds(60))
            if room == .city {
                home?.stop()
                let built = CityRoomScene()
                city = built
                NookiPerf.shown(built, kind: .city)
            } else {
                city?.stop()
                city = nil
                if let home { NookiPerf.shown(home, kind: .home) }
            }
            if let scene {
                let start = scene.frame
                let deadline = ContinuousClock.now + .seconds(2)
                while scene.frame == start, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(8))
                }
            }
            withAnimation(.easeInOut(duration: 0.25)) { roomLive = true }
            try? await Task.sleep(for: .milliseconds(300))
            if roomLive { worldSnapshot = nil }
            switchingRoom = false
        }
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
}

/// Names the animation of the showcase that is playing.
private struct ShowcaseLabel: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text(label)
                .contentTransition(.opacity)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .warmGlass(.capsule)
        .frame(height: 44)
        .accessibilityLabel("Playing \(label)")
    }
}
