import FeatureShop
import FeatureUs
import DecorInterface
import FeatureDecor
import FeatureGames
import FeatureInbox
import MomentsInterface
import ServerSync
import WidgetInterface
import WidgetUI
import ProfileInterface
import RoomInterface
import SwiftUI
import Design
import TipKit
import Transport
import UsInterface
import WidgetBridge
import Wire

struct HomeView: View {
    /// Owned by OurioApp: a `@State` default here would read every store again on each pass of the app's `body`.
    @Binding var state: HomeState
    @State var room = RoomController()
    /// The splash stays over everything until the room has loaded (see `lift()`).
    @State private var launching = true
    /// The tab bar's top edge, global, which a purchase's card keeps clear of.
    @State private var tabBarTop: CGFloat?
    /// The splash is still drawn while it fades out after `launching` ends, though it takes no touches by then.
    @State private var splashDrawn = true
    /// The screen as the World last showed it, held up on the way back until the room draws again.
    @State private var worldSnapshot: UIView?
    /// Whether the room has drawn since the World came back; until then `worldSnapshot` stands in for it.
    @State private var roomLive = true
    /// Counts the World coming on screen; a return's task acts only while it is still the latest one.
    @State private var worldShows = 0
    /// The World as it was when a tab switch left it, fading out under the page coming in.
    @State private var worldLeaving: UIView?
    /// A room switch is under way; another waits for it.
    @State private var switchingRoom = false
    /// Nil without a server to buy packs through.
    @State private var coinPacks: CoinPacksModel?
    @State private var coinsShown: CoinsAsk?
    /// What the partner did while this phone was away, shown a few seconds after coming back.
    @State private var homecoming: HomecomingLine?
    /// The header and the tab bar as a perf run wants them drawn; glass, as shipped, otherwise.
    @State private var hud = HUDArm.launch
    @State private var sheetGround = SheetGroundStyle.opaque
    /// Labs → Performance: suspects switched off while the app runs, and its frame meter.
    @State private var perfLab = PerfLab(defaults: .standard)
    @State private var tabClock = TabSwitchClock()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Hints.self) var hints
    @Environment(ServerSession.self) var session: ServerSession?
    @AppStorage(AppSettings.brainCardKey) private var brainCard = false
    @AppStorage(AppSettings.quietRoomKey) private var quietChrome = QuietChrome.dim
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var quiet = QuietRoom.store()
    var hasRoomChoice: Bool { state.rooms.variant.hasRoomChoice }
    @State private var height: CGFloat = 0
    /// The rooms already counted as opened since the app came to the front, so each is reported once.
    @State var reportedRooms: Set<RoomKind> = []

    private var showsBoard: Bool { state.tab == .moments && state.momentsMode == .board }
    private var showsRoom: Bool { state.tab == .world || showsBoard }
    /// Something hides the room whole, or near enough: the canvas, the Inbox, the composer, the profile with its
    /// Settings, the Coins sheet, or the app not in front. The sheets that open at their content's height (the pet,
    /// an item, the mood) leave the room showing, and live.
    private var roomCovered: Bool {
        state.drawing || state.showsInbox || state.composingNote != nil || state.showsProfile || coinsShown != nil
            || scenePhase != .active
    }
    private var roomOnScreen: Bool { showsRoom && !roomCovered }
    /// The World's room can be seen; when it can't, its last frame is kept to show on the way back.
    private var worldOnScreen: Bool { state.tab == .world && !roomCovered }
    /// The World's chrome may step back while she is only watched.
    private var quietAllowed: Bool {
        quietChrome != .off && !QuietRoom.scripted && !voiceOver && !launching && worldOnScreen && room.game == nil
    }

    /// In three parts: as one modifier chain, `body` takes the Release type-checker past its time limit on Xcode 26.
    var body: some View {
        presenting(following(layout))
    }

    private func following(_ content: some View) -> some View {
        content
        .modifier(StreakNudging(streak: state.streak))
        .task {
            LaunchSignposts.event("home first frame")
            OurioPerf.start(state: state, hud: { hud = $0 }, sheetGround: { sheetGround = $0 }, selectRoom: select)
            await lift()
        }
        .onChange(of: state.shop.owned, initial: true) { _, owned in state.decor.send(.owned(owned)) }
        .onChange(of: state.shop.serverLayout, initial: true) { _, layout in
            state.decorSync.client = { [weak session] in session?.shopSync }
            state.decorSync.heard(layout, stowed: state.shop.serverStowed)
        }
        .onChange(of: state.shop.serverStowed) { _, stowed in
            state.decorSync.heard(state.shop.serverLayout, stowed: stowed)
        }
        .task {
            if let item = UserDefaults.standard.string(forKey: "decorate") { state.decor.send(.opened(item: item == "closet" ? nil : item)) }
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
            if new { worldShows += 1 }
            if new, room.hasHome, worldSnapshot != nil {
                roomLive = false
                let show = worldShows
                let current = { show == worldShows && worldOnScreen }
                Task {
                    await room.nextFrame()
                    guard current() else { return }
                    withAnimation(Motion.fade()) { roomLive = true }
                    try? await Task.sleep(for: .milliseconds(250))
                    if current(), roomLive { worldSnapshot = nil }
                }
            }
        }
        .onChange(of: state.tab) { _, tab in
            tabClock.began(tab.title)
            OurioPerf.tabShown(tab)
            if tab == .world { room.perfShown(state.room) }
            // A fade cut short by a quick return never comes back over a later switch.
            if tab == .world { worldLeaving = nil }
            if tab != .world, hasRoomChoice { prepareRooms() }
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
        .onChange(of: quietAllowed, initial: true) { _, allowed in quiet.send(.allowed(allowed)) }
    }

    private func presenting(_ content: some View) -> some View {
        content
        .sheet(item: $state.composingNote) { mode in
            NoteComposer(state: state, mode: mode)
        }
        .sheet(isPresented: $state.showsInbox) {
            if let inbox = session?.inbox {
                InboxSheet(model: inbox, state: state) { target in
                    withAnimation(Motion.spring(0.4)) { state.open(target) }
                }
            } else {
                InboxSignedOut(petName: state.petName, isPaired: state.profile.couple.pair != nil)
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
            withAnimation(Motion.spring(0.4)) { state.open(link) }
        }
        .environment(\.sheetGround, sheetGround)
        .environment(perfLab)
        #if DEBUG || LABS_YES
        .onAppear { perfLab.statsSource = { [room] tier in room.roomStats(tier: tier) } }
        .onChange(of: perfLab.state, initial: true) { _, state in room.setPerf(state) }
        #endif
    }

    private var layout: some View {
        ZStack {
            // The bokeh drifts only around a room: under the Shop, Moments and Us it holds still, so their scrolling
            // and the glass over them never redraw a moving backdrop every frame.
            WarmBackdrop(drifts: roomOnScreen && perfLab.isOn(.drift) && perfLab.tier.plan.sway)

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
            .perfLab(perfLab)
            // Tab to tab, the new page is all there in its first frame, as with the system's tab bar: a fade in
            // would show it half drawn for its first tenth of a second. The header and the tab bar stay put.
            .transition(.identity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The same header, in the same place, on every tab, and the tab bar: bars over the tab, so its scroll
            // view runs full-bleed under both and only its content is inset.
            .bars(fades: !showsRoom, softEdges: perfLab.isOn(.scrollEdges)) {
                if hud != .hidden {
                    AppHeader(state: state, erase: {
                        room.stop()
                        HomeState.eraseAll()
                        state = HomeState(stores: .live())
                        Task { await followPair() }
                    }) {
                        if state.tab == .world {
                            RoomSwitch(state: state, select: select).transition(.opacity)
                        } else if state.tab == .moments {
                            MomentsSwitch(state: state).transition(.opacity)
                        } else if state.tab == .shop {
                            ShopChips(state: state).transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.xs)
                    .environment(\.glassRendering, barGlass)
                }
            } bottom: {
                if hud != .hidden {
                    TabBar(state: state)
                        .opacity(arranging ? 0 : 1)
                        .allowsHitTesting(!arranging)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { tabBarTop = $0 }
                        .padding(.horizontal, Space.l)
                        .environment(\.glassRendering, barGlass)
                }
            }
            .modifier(QuietFade(store: quiet, chrome: quietChrome))
            .opacity(room.game == nil ? 1 : 0)

            // Over the chrome: while a game is played nothing else of Home shows.
            RoomGameLayer(controller: room)

            // The composer and the canvas play it over themselves while they're up.
            if state.composingNote == nil, !state.drawing {
                PurchaseMoment(state: state, floor: hud == .hidden ? nil : tabBarTop)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        // Above the tab bar, so both stay clear of the "+" in the right corner.
        .overlay(alignment: .bottom) {
            ZStack {
                if state.tab == .world, room.game == nil, !arranging { petControls }
            }
            .animation(Motion.fade(), value: state.tab)
            .modifier(QuietFade(store: quiet, chrome: quietChrome))
        }
        .overlay {
            if arranging, room.game == nil, state.tab == .world { DecorTouchLayer(controller: room) }
        }
        .overlay(alignment: .bottom) {
            if arranging, room.game == nil {
                DecorPanel(state: state) { state.decor.send(.closed) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.spring(0.3), value: arranging)
        .background { TouchWatcher { [quiet] in quiet.send(.touched) } }
        #if DEBUG || LABS_YES
        .overlay(alignment: .topTrailing) {
            if perfLab.state.meter {
                PerfLabMeter(lab: perfLab, room: roomInput.visibility, tabs: tabClock.times)
                    .padding(.trailing, Space.l)
                    .padding(.top, Space.xl * 2)
            }
        }
        #endif
        .overlay(alignment: .topLeading) {
            if brainCard && state.tab == .world {
                RoomBrainCard(controller: room)
                .padding(.leading, Space.l)
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
                    .accessibilityLabel("Ourio is opening")
                    .accessibilityIdentifier("launch-splash")
                    .opacity(launching ? 1 : 0)
                    .scaleEffect(launching ? 1 : 1.08)
                    .allowsHitTesting(launching)
                    .accessibilityHidden(!launching)
            }
        }
    }

    private var petControls: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let homecoming {
                HomecomingLabel(line: homecoming)
                    .transition(.opacity)
            }
            HStack(alignment: .bottom) {
                PetButton(state: state, needs: { room }) { room.play($0) }
                Spacer(minLength: 0)
                if let showcase = room.showcase { ShowcaseLabel(label: showcase) }
                if state.room == .home {
                    let waiting = state.decor.state.closetCount
                    GlassIconButton(
                        symbol: "sofa.fill", label: "Decorate", badge: waiting > 0 ? .count(waiting) : .none
                    ) { state.decor.send(.opened(item: nil)) }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityIdentifier("decorate")
                }
            }
            .padding(.horizontal, Space.xs)
        }
        .padding(.horizontal, Space.m)
        .padding(.bottom, 94)
        .transition(.opacity)
        .task(id: homecoming) {
            guard homecoming != nil else { return }
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            withAnimation(.easeOut(duration: 0.6)) { homecoming = nil }
        }
    }

    /// Its own method: inline in `body`, the closure tips the type-checker over its time limit.
    private func phaseChanged(from old: ScenePhase, to phase: ScenePhase) {
        switch phase {
        case .active:
            // The first call is launch, where every store has just been read.
            state.refresh(reloading: old != phase)
            for _ in 0..<state.takeWidgetFeeds() { room.feed() }
            room.appOpened()
            state.sendPronouns = { room.pronounsChosen() }
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
                state.refreshPronouns()
                await state.streak.refresh()
            }
            // The room socket sends no game frames it missed while the app was away. Its own task, so missed
            // photos downloading above don't hold it up.
            Task { await session?.whoKnows.load() }
            session?.reactions?.refresh()
            session?.followInbox(
                true, photos: photoSync, texts: textSync, shop: state.shop, lists: state.lists,
                moods: { [state] in state.moodSync?.received($0) }, streak: state.streak,
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
        try? await Task.sleep(for: .seconds(1.6))
        await room.ready(timeout: .seconds(4.4))
        LaunchSignposts.event("room ready")
        // A few frames for the last loaded pieces to draw.
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(Motion.fade(0.8)) { launching = false } completion: { splashDrawn = false }
        LaunchSignposts.event("splash lifting")
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
        await ShopView.prewarm(state.shop.offers)
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
        withAnimation(Motion.spring(0.25)) { state.room = kind }
        Task {
            // One pass for the stand-in to be on screen before the room under it changes.
            try? await Task.sleep(for: .milliseconds(60))
            self.room.show(kind.scene)
            self.room.perfShown(kind)
            await self.room.nextFrame()
            withAnimation(Motion.fade(0.25)) { roomLive = true }
            try? await Task.sleep(for: .milliseconds(300))
            if roomLive { worldSnapshot = nil }
            switchingRoom = false
        }
    }

    /// The other rooms are built under a tab, once its page has faded in and holds still, so the first switch to
    /// one doesn't build it in front of the cat.
    private func prepareRooms() {
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard state.tab != .world else { return }
            for kind in state.rooms.variant.kinds { room.prepare(kind.scene) }
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    /// The header's and the tab bar's glass: a perf run's arm, flat while Labs → Performance has it off.
    private var barGlass: GlassRendering { perfLab.isOn(.barGlass) ? hud.glass : .flat }

    private var roomInput: RoomInput {
        let plan = perfLab.tier.plan
        let visibility: RoomVisibility =
            roomOnScreen && !plan.still ? .visible : (showsRoom ? .covered : .hidden)
        let rate = perfLab.isOn(.splatRate) ? 30 : 0
        return RoomInput(
            scene: showsBoard ? .board : state.room.scene, coat: CatCoat.current(), visibility: visibility,
            catName: state.petName, catPronouns: state.pronouns, partnerHere: session?.partnerHere == true,
            motes: perfLab.isOn(.motes) && plan.motes,
            sway: perfLab.isOn(.sway) && plan.sway, decor: roomDecor,
            rendering: RoomRendering(
                antialiasing: perfLab.isOn(.msaa) && plan.antialiasing, hdr: perfLab.isOn(.hdr),
                splatRate: [rate, plan.splatRate].filter { $0 > 0 }.min() ?? 0))
    }

    private var arranging: Bool { state.decor.state.isArranging }

    private var roomDecor: RoomDecor {
        let arranging = state.decor.state
        let mode: RoomDecor.Mode =
            arranging.isArranging ? .arranging(selected: arranging.selection, fits: arranging.isValid, ghost: arranging.origin) : .showing
        return RoomDecor(layout: arranging.layout, mode: mode)
    }

    private func handle(_ event: RoomEvent) {
        switch event {
        case .decor(let gesture): handleDecor(gesture)
        case .catPetted: withAnimation(Motion.spring(0.4)) { state.care.pet() }
        case .pinOpened(let id): state.openedPin = PinRoute(id: id)
        case .drawAsked: state.composingNote = .draw
        case .careAsked: state.showsPetSheet = true
        case .partnerCared(let care):
            withAnimation(Motion.spring(0.3)) {
                homecoming = HomecomingLine(care, partner: state.otherPartner, cat: CatProfile.name())
            }
        }
    }

    private func handleDecor(_ gesture: DecorGesture) {
        switch gesture {
        case .tapped(let id): state.decor.send(.roomTapped(id))
        case .tappedEmpty: state.decor.send(.emptyTapped)
        case .dragBegan(let id): state.decor.send(.dragBegan(id))
        case .dragged(let placement): state.decor.send(.dragged(placement))
        case .dropped: state.decor.send(.dropped)
        case .cancelled: state.decor.send(.dragCancelled)
        }
    }

    private var wallPins: [Moment]? { room.hasHome ? state.moments.pinned : nil }
}

private struct ShowcaseLabel: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text(label)
                .contentTransition(.opacity)
        }
        .ourioScaledFont(size: 14, weight: .semibold, design: .rounded, relativeTo: .subheadline)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .foregroundStyle(Ink.glassGlyph)
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s)
        .frame(minHeight: 40)
        .glass(.capsule, role: .bar)
        .frame(minHeight: Size.control)
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
