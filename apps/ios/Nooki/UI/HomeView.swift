import FeatureGames
import RoomInterface
import SwiftUI
import Design
import TipKit
import Transport
import WidgetBridge
import Wire

struct HomeView: View {
    /// Owned by NookiApp: a `@State` default here would read every store again on each pass of the app's `body`.
    @Binding var state: HomeState
    /// The room and the cat in it: the scenes, the games, her status. Nothing here reads them.
    @State var room = RoomController()
    /// The splash stays over everything until the room has loaded (see `lift()`).
    @State private var launching = true
    /// The splash is still drawn while it fades out after `launching` ends, though it takes no touches by then.
    @State private var splashDrawn = true
    /// The screen as the World last showed it, held up on the way back until the room draws again.
    @State private var worldSnapshot: UIView?
    /// Whether the room has drawn since the World came back; until then `worldSnapshot` stands in for it.
    @State private var roomLive = true
    /// The World's room may be mounted: false off the World, and on the way back until the switch has played (see
    /// `returnRoom`).
    @State private var roomInWorld = true
    /// The World as it was when a tab switch left it, fading out under the page coming in.
    @State private var worldLeaving: UIView?
    /// The tab the last switch came from, which sets the side the new page comes in from.
    @State private var tabFrom = HomeTab.world
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A room switch is under way; another waits for it.
    @State private var switchingRoom = false
    /// The Coins sheet's packs, once there is a server to buy them through.
    @State private var coinPacks: CoinPacksModel?
    /// The Coins sheet on screen, a moment after the shop asked for it.
    @State private var coinsShown: CoinsAsk?
    /// The header and the tab bar as a perf run wants them drawn; glass, as shipped, otherwise.
    @State private var hud = HUDArm.launch
    @State private var sheetGround = SheetGroundStyle.opaque
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
    /// Something hides the room whole, or near enough: the canvas, the Inbox, the composer, the profile with its
    /// Settings, the Coins sheet, or the app not in front. The sheets that open at their content's height (the pet,
    /// an item, the mood) leave the room showing, and live.
    private var roomCovered: Bool {
        state.drawing || state.showsInbox || state.composingNote != nil || state.showsProfile || coinsShown != nil
            || scenePhase != .active
    }
    /// The room's tab is up and its room may be mounted.
    private var roomShown: Bool { state.tab == .world && roomInWorld || showsBoard }
    /// The room is mounted only while it can be seen.
    private var roomOnScreen: Bool { roomShown && !roomCovered }
    /// The World's room can be seen; when it can't, its last frame is kept to show on the way back.
    private var worldOnScreen: Bool { state.tab == .world && !roomCovered }

    /// In three parts: as one chain of modifiers, `body` takes the Release type-checker past its time limit on Xcode 26.
    var body: some View {
        presenting(following(layout))
    }

    /// The room's tasks and what it follows in the state.
    private func following(_ content: some View) -> some View {
        content
        .task {
            NookiPerf.start(state: state, hud: { hud = $0 }, sheetGround: { sheetGround = $0 })
            await lift()
        }
        .task {
            room.load()
            for await event in room.events { handle(event) }
        }
        // Nil until the room exists, so the photos are printed once it does and again only when the pins change.
        .task(id: wallPins) {
            guard room.hasHome else { return }
            let images = await state.moments.filmPrints(for: state.moments.pinned, maxPixels: MomentStore.wallPixels)
            if !Task.isCancelled { room.setPolaroids(images) }
        }
        .task(id: boardKey + [room.hasBoard ? "board" : ""]) {
            guard room.hasBoard else { return }
            let pins = await BoardFaces.pins(state: state)
            if !Task.isCancelled { room.setPins(pins) }
        }
        .onChange(of: showsBoard) { _, new in
            // DioramaView swaps the root by itself; the room that was showing stops so two never drive at once.
            room.show(new ? .board : state.room.scene)
        }
        // Settings › Labs asks for the showcase, once it is closed.
        .onChange(of: state.showcaseRequested) { _, requested in
            guard requested else { return }
            state.showcaseRequested = false
            room.playAll()
        }
        .onChange(of: state.room) {
            room.clearShowcase()
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
                // A second copy: one view can't be on screen twice, and a quick return shows the first again.
                if state.tab != .world, worldSnapshot != nil {
                    worldLeaving = Self.keyWindow?.snapshotView(afterScreenUpdates: false)
                }
            }
            if new, room.hasHome, worldSnapshot != nil {
                roomLive = false
                let held = !roomInWorld
                Task {
                    if held, !(await returnRoom()) { return }
                    await room.nextFrame()
                    withAnimation(Motion.fade()) { roomLive = true }
                    try? await Task.sleep(for: .milliseconds(250))
                    if roomLive { worldSnapshot = nil }
                }
            }
        }
        .onChange(of: state.tab) { _, tab in
            NookiPerf.tabShown(tab)
            if tab == .world { room.perfShown(state.room) }
            tabFrom = tab
            // A fade cut short by a quick return never comes back over a later switch.
            if tab == .world { worldLeaving = nil }
            if tab != .world {
                roomInWorld = false
            } else if worldSnapshot == nil || !room.hasHome || roomCovered {
                // Nothing to stand in for the room, or a cover over it: no switch to play out first.
                roomInWorld = true
            }
        }
        // Pets from the widget and the control reach Mochi when the app comes back.
        .onChange(of: state.care.petPulse) {
            room.purr()
            hints.done(PetHint())
        }
        .onChange(of: state.care.treatsGiven) { hints.done(TreatHint()) }
        .onChange(of: state.tab, initial: true) { visitHints() }
        .task { hints.isHeldOut = { [rooms = state.rooms] in rooms.remote.variant(of: Experiments.hints) == HintHoldout.hold } }
        .onChange(of: scenePhase, initial: true) { old, phase in phaseChanged(from: old, to: phase) }
    }

    /// The sheets and the canvas over Home, and what the app hears from outside.
    private func presenting(_ content: some View) -> some View {
        content
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
        .task { loadCoinPacks() }
        .task(id: session?.isPaired) { await followPair() }
        .modifier(ResendsUnsent(
            paired: session?.isPaired == true, photos: state.moments.unsent.map(\.id), notes: state.notes.unsent.map(\.id),
            sendPhotos: { await photoSync?.sendUnsent() ?? false },
            sendNotes: { await textSync?.sendUnsent() ?? false },
            sendCatEvents: { await room.flushCat() }))
        .onReceive(NotificationCenter.default.publisher(for: .pushTokenChanged)) { _ in
            Task { await session?.drawingSync?.registerPushTokens() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .coupleChanged)) { _ in state.profile.reload() }
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            withAnimation(.spring(duration: 0.4)) { state.open(link) }
        }
        .environment(\.sheetGround, sheetGround)
    }

    private var layout: some View {
        ZStack {
            // The bokeh drifts only around a room: under the Shop, Moments and Us it holds still, so their scrolling
            // and the glass over them never redraw a moving backdrop every frame.
            WarmBackdrop(drifts: roomOnScreen)

            // The City window's view, seen through the hole in the room's wall; never takes a touch.
            RoomHost(input: roomInput, controller: room).equatable()

            // A new RealityView takes a moment to draw its first frame; the last one shows meanwhile.
            if state.tab == .world, !roomLive || roomCovered, let worldSnapshot {
                SnapshotView(view: worldSnapshot)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // The room goes at once when the World is left; its last frame fades with the rest of the World.
            if state.tab != .world, let worldLeaving {
                LeavingSnapshot(view: worldLeaving) {
                    if self.worldLeaving === worldLeaving { self.worldLeaving = nil }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
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
                    // The room switch is in the header's bar, so it shares the header's glass container.
                    Color.clear
                }
            }
            // Tab to tab, the page alone moves; the header and the tab bar are outside it and stay put. Read in the
            // pass that switches, `tabFrom` is still the tab left.
            .transition(.page(HomeTab.direction(from: tabFrom, to: state.tab), reduceMotion: reduceMotion))
            .animation(Motion.spring(), value: state.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The same header, in the same place, on every tab, and the tab bar: bars over the tab, so its scroll
            // view runs full-bleed under both and only its content is inset.
            .bars(fades: !showsRoom) {
                if hud != .hidden {
                    AppHeader(state: state, erase: {
                        room.stop()
                        HomeState.eraseAll()
                        state = HomeState(stores: .live())
                        Task { await followPair() }
                    }) {
                        if state.tab == .world {
                            RoomSwitch(state: state, select: select).transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .environment(\.glassRendering, hud.glass)
                }
            } bottom: {
                if hud != .hidden {
                    TabBar(state: state)
                        .padding(.horizontal, 16)
                        .environment(\.glassRendering, hud.glass)
                }
            }
            .opacity(room.game == nil ? 1 : 0)

            // Over the chrome: while a game is played nothing else of Home shows.
            RoomGameLayer(controller: room)

            // The composer and the canvas play it over themselves while they're up.
            if state.composingNote == nil, !state.drawing { PurchaseMoment(state: state) }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        // Above the tab bar, so both stay clear of the "+" in the right corner.
        .overlay(alignment: .bottom) {
            ZStack {
                if state.tab == .world, room.game == nil { petControls }
            }
            .animation(Motion.fade(), value: state.tab)
        }
        .overlay(alignment: .topLeading) {
            if brainCard && state.tab == .world {
                RoomBrainCard(controller: room)
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
    }

    /// The pet button and the hints over it.
    private var petControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Above the portrait, with the arrow down at it, so the hint never covers her.
            TipView(PetHint(), arrowEdge: .bottom)
            TipView(TreatHint(), arrowEdge: .bottom)
            HStack(alignment: .bottom) {
                PetButton(state: state, needs: { room }) { room.play($0) }
                Spacer(minLength: 0)
                if let showcase = room.showcase { ShowcaseLabel(label: showcase) }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 94)
        .transition(.opacity)
    }

    /// Its own method: inline in `body`, the closure tips the type-checker over its time limit.
    private func phaseChanged(from old: ScenePhase, to phase: ScenePhase) {
        switch phase {
        case .active:
            // The first call is launch, where every store has just been read.
            state.refresh(reloading: old != phase)
            room.appOpened()
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
            // The pair's cat and streak catch up, and what this phone did offline goes. Their own task, so a slow
            // download above doesn't hold them up.
            Task {
                await room.syncCat()
                await state.streak.refresh()
            }
            // The room socket sends no game frames it missed while the app was away. Its own task, so missed
            // photos downloading above don't hold it up.
            Task { await session?.whoKnows.load() }
            session?.reactions?.refresh()
            session?.followInbox(
                true, photos: photoSync, texts: textSync, shop: state.shop, lists: state.lists,
                moods: { [state] in state.moodSync?.received($0) },
                cat: { [room] in room.catEntryArrived($0) }, lastCatSeq: { [room] in room.lastCatSeq })
            refreshRooms()
            if !launching { reportOpened(state.room) }
        case .background:
            state.didEnterBackground()
            session?.followInbox(false)
            reportedRooms = []
        default: break
        }
    }

    /// Its own method: inline in `body`, the closure tips the Release type-checker over its time limit on Xcode 26.
    private func loadCoinPacks() {
        guard coinPacks == nil, let payments = session?.payments else { return }
        let shop = state.shop
        coinPacks = CoinPacksModel(payments: payments) {
            await shop.refresh()
            await shop.loadHistory()
        }
    }

    /// Lifts the splash once the room is ready, never sooner than its own little intro and never later than 6 s.
    private func lift() async {
        let start = Date()
        while launching {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 6 || elapsed > 1.6 && room.isReady { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // A few frames for the last loaded pieces to draw.
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: 0.8)) { launching = false } completion: { splashDrawn = false }
        // `-room city` on launch opens the City room, for recordings and screenshots.
        if UserDefaults.standard.string(forKey: "room") == "city" || state.rooms.variant.firstRoom == .city {
            select(.city)
        } else if room.hasHome {
            room.perfShown(.home)
        }
        #if DEBUG
        // `-tab shop` opens the Shop, for screenshots.
        if UserDefaults.standard.string(forKey: "tab") == "shop" { state.tab = .shop }
        #endif
        reportOpened(state.room)
    }

    /// Visits another room with one crossfade: the screen as it is stands in over the swap, and fades out once the
    /// new room has drawn. The City is built under the stand-in, which hides the moment it holds the main thread.
    private func select(_ kind: RoomKind) {
        guard kind != state.room, !switchingRoom else { return }
        if kind == .city { hints.done(RoomsHint()) }
        switchingRoom = true
        worldSnapshot = Hints.keyWindowIsPresenting() ? nil : Self.keyWindow?.snapshotView(afterScreenUpdates: false)
        var still = Transaction(animation: nil)
        still.disablesAnimations = true
        withTransaction(still) { roomLive = false }
        // The switch moves at once; the room under the stand-in follows it.
        withAnimation(.snappy(duration: 0.25)) { state.room = kind }
        Task {
            // One pass for the stand-in to be on screen before the room under it changes.
            try? await Task.sleep(for: .milliseconds(60))
            self.room.show(kind.scene)
            self.room.perfShown(kind)
            await self.room.nextFrame()
            withAnimation(.easeInOut(duration: 0.25)) { roomLive = true }
            try? await Task.sleep(for: .milliseconds(300))
            if roomLive { worldSnapshot = nil }
            switchingRoom = false
        }
    }

    /// Mounts the World's room once the switch back to it has played: the mount holds the main thread for one long
    /// frame, which would freeze the switch halfway; under the snapshot it freezes a still screen. False when the
    /// World was left again meanwhile.
    private func returnRoom() async -> Bool {
        try? await Task.sleep(for: .seconds(Motion.quick))
        guard state.tab == .world else { return false }
        roomInWorld = true
        return true
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    /// What the room is told to show, from the shell's coarse state.
    private var roomInput: RoomInput {
        let visibility: RoomVisibility =
            roomOnScreen ? .visible : (roomShown ? .covered : .hidden)
        return RoomInput(
            scene: showsBoard ? .board : state.room.scene, coat: CatCoat.current(), visibility: visibility)
    }

    private func handle(_ event: RoomEvent) {
        switch event {
        case .catPetted: withAnimation(.spring(duration: 0.4)) { state.care.pet() }
        case .pinOpened(let id): state.openedPin = PinRoute(id: id)
        case .drawAsked: state.composingNote = .draw
        }
    }

    /// The moments on the room's wall, nil until the room exists.
    private var wallPins: [Moment]? { room.hasHome ? state.moments.pinned : nil }
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
        .foregroundStyle(Ink.glassGlyph)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glass(.capsule, role: .bar)
        .frame(height: 44)
        .accessibilityLabel("Playing \(label)")
    }
}

/// A snapshot that starts fading out the moment it shows, and says when it is gone.
private struct LeavingSnapshot: View {
    let view: UIView
    let gone: () -> Void
    @State private var shown = true

    var body: some View {
        SnapshotView(view: view)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(Motion.fade()) { shown = false } completion: { gone() } }
            .id(ObjectIdentifier(view))
    }
}
