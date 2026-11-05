import FeatureGames
import SwiftUI
import TipKit
import WidgetBridge
import Wire

struct HomeView: View {
    @State private var state = HomeState()
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
    /// The room's one view, kept across tabs (see `KeptRoomView`).
    @State private var roomHost = RoomHost()
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

    var body: some View {
        ZStack {
            // The bokeh drifts only around a room: under the Shop, Moments and Us it holds still, so their scrolling
            // and the glass over them never redraw a moving backdrop every frame.
            WarmBackdrop(drifts: showsRoom)

            if Self.noRoom {
                // A stand-in for the room under the UI tests, which cannot draw RealityKit on CI's virtual Macs.
                Color.clear
                    .contentShape(.rect)
                    .allowsHitTesting(showsRoom)
                    .modifier(RoomTapCounter())
                    .ignoresSafeArea()
            } else if let scene, showsRoom {
                // Only while a room shows: a paused RealityView left in place under the Shop, Moments and Us still
                // runs its render loop and composites a full-screen layer every frame. The room itself stays loaded
                // (CatRoom), so coming back only makes a new view for it.
                let room = DioramaView(scene: scene, paused: !showsRoom, petPulse: state.petPulse) {
                    withAnimation(.spring(duration: 0.4)) { state.pet() }
                }
                KeptRoomView(host: roomHost, room: room)
                .opacity(showsRoom ? 1 : 0)
                .allowsHitTesting(showsRoom && state.game == nil)
                .modifier(RoomTapCounter())
                .ignoresSafeArea()
            }

            // A new RealityView takes a moment to draw its first frame; the last one shows meanwhile.
            if state.tab == .world, !roomLive, let worldSnapshot {
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
                    state = HomeState()
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
        // Over the room rather than in place of it: RealityKit keeps drawing underneath, so the room is already
        // warmed up and whole when the splash lifts.
        .overlay {
            if launching {
                LaunchSplash()
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
            }
        }
        .task {
            NookiPerf.start(state: state)
            await lift()
        }
        .task {
            guard home == nil, !Self.noRoom else { return }
            let room = DioramaScene()
            home = room
            room.setPolaroids(await state.moments.filmPrints(for: state.moments.pinned, maxPixels: MomentStore.wallPixels))
        }
        .task(id: state.moments.pinned) {
            let images = await state.moments.filmPrints(for: state.moments.pinned, maxPixels: MomentStore.wallPixels)
            if !Task.isCancelled { home?.setPolaroids(images) }
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
        .onChange(of: state.tab) { old, new in
            // The room view goes with the World (see above): keep what it showed, to show again on the way back.
            if old == .world, !showsRoom {
                worldSnapshot = Self.keyWindow?.snapshotView(afterScreenUpdates: false)
            }
            if new == .world, let scene, worldSnapshot != nil {
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
        .onChange(of: state.petPulse) {
            scene?.purr()
            hints.done(PetHint())
        }
        .onChange(of: state.treatsGiven) { hints.done(TreatHint()) }
        // A run of pets is one in the pair's journal and Inbox: one every 10 minutes at most.
        .onChange(of: state.petsGiven) {
            guard let session, Date.now.timeIntervalSince(petSentAt) > 600 else { return }
            petSentAt = .now
            Task { await session.catEvents.send([.petted]) }
        }
        .onChange(of: state.tab, initial: true) { visitHints() }
        .onChange(of: state.lastPurchase) { _, purchase in
            guard let purchase, purchase.kind == .ink, let inkSync else { return }
            Task { await inkSync.settle(purchase, state) }
        }
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
                    await inkSync?.refresh(state)
                }
                session?.reactions?.refresh()
                session?.followInbox(true, photos: photoSync, texts: textSync)
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
        .sheet(item: $state.openedShopItem) { item in
            ItemSheet(item: item, state: state)
        }
        .fullScreenCover(isPresented: $state.drawing) {
            LockCanvasView(
                state: state, api: session?.api,
                model: DrawModel(room: session?.liveRoom(), partnerName: state.otherPartner))
        }
        .task { await DrawingSync.watchLiveActivities() }
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
        scene?.stop()
        if room == .city {
            // After the tap has drawn; until then the home room stays on screen.
            Task {
                if state.room == .city, city == nil { city = CityRoomScene() }
                if let city { NookiPerf.shown(city, kind: .city) }
            }
        } else {
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

    /// The ids of the newest notes on the board; a new set rebuilds their faces.
    private var boardKey: [String] { BoardFaces.key(state: state) }

    /// Photos to and from the partner; nil until this phone is paired with them.
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
            let buying = state.lastPurchase?.canUndo(at: .now) == true
            return HintContext(
                screen: screen, busy: sheet || buying || showcase != nil, hasRoomChoice: hasRoomChoice,
                canAffordTreat: state.coins >= HomeState.treatPrice)
        }
    }

    private var inkSync: InkSync? {
        guard let session, session.isPaired else { return nil }
        return InkSync(api: session.api)
    }

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
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(state.room == room ? .isSelected : [])
            }
        }
        .padding(3)
        .warmGlass(.capsule)
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
            .warmGlass(.capsule, interactive: true)
        }
        .buttonStyle(.plain)
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

/// Holds the room's view and what goes with it, made once and kept while the room is off screen.
@MainActor
private final class RoomHost {
    private var controller: UIHostingController<DioramaView>?

    func view(showing room: DioramaView) -> UIView {
        if let controller {
            controller.rootView = room
            return controller.view
        }
        let controller = UIHostingController(rootView: room)
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        self.controller = controller
        return controller.view
    }

    func show(_ room: DioramaView) { controller?.rootView = room }
}

/// The room's view, the same one every time it shows. Out of the window it neither draws nor composites, and back
/// in it carries on from its last frame instead of setting up a new renderer.
private struct KeptRoomView: UIViewRepresentable {
    let host: RoomHost
    let room: DioramaView

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        let view = host.view(showing: room)
        view.removeFromSuperview()
        view.frame = holder.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
        return holder
    }

    func updateUIView(_ holder: UIView, context: Context) { host.show(room) }

    static func dismantleUIView(_ holder: UIView, coordinator: ()) {
        for view in holder.subviews { view.removeFromSuperview() }
    }
}

/// Dark amber vignette with drifting bokeh, standing in for the depth-of-field blur of the reference.
private struct WarmBackdrop: View {
    /// Whether the bokeh moves; when it doesn't, it stays where it was.
    var drifts = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0xF4BF7E), Color(hex: 0xB36E3A), Color(hex: 0x4A2C1B), Color(hex: 0x24150D)],
                center: UnitPoint(x: 0.5, y: 0.48),
                startRadius: 10,
                endRadius: 520
            )
            TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active || !drifts)) { context in
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
