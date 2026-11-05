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
    /// The splash stays over everything until the room has loaded (see `lift()`).
    @State private var launching = true
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
            WarmBackdrop()

            if Self.noRoom {
                // A stand-in for the room under the UI tests, which cannot draw RealityKit on CI's virtual Macs.
                Color.clear
                    .contentShape(.rect)
                    .allowsHitTesting(showsRoom)
                    .modifier(RoomTapCounter())
                    .ignoresSafeArea()
            } else if let scene {
                DioramaView(scene: scene, paused: !showsRoom, petPulse: state.petPulse) {
                    withAnimation(.spring(duration: 0.4)) { state.pet() }
                }
                .opacity(showsRoom ? 1 : 0)
                .allowsHitTesting(showsRoom)
                .modifier(RoomTapCounter())
                .ignoresSafeArea()
            }

            VStack(spacing: 12) {
                // The same header, in the same place, on every tab.
                AppHeader(state: state)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                Group {
                    switch state.tab {
                    case .shop:
                        // The scroll view runs under the tab bar and keeps its own 16pt margins.
                        ShopView(state: state)
                    case .moments:
                        MomentsView(state: state)
                    case .world:
                        VStack(spacing: 16) {
                            RoomControls(state: state, showcase: showcase, select: select) { scene?.playAll() }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 82)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 12)))
                .frame(maxHeight: .infinity, alignment: .top)
            }

            VStack {
                Spacer(minLength: 0)
                TabBar(state: state)
                    .padding(.horizontal, 16)
            }

            PurchaseMoment(state: state)
        }
        // Bottom left, so it stays clear of the "+" in the right corner.
        .overlay(alignment: .bottomLeading) {
            if state.tab == .world {
                PetButton(state: state, needs: { scene?.director }) { scene?.playAll() }
                    .padding(.leading, 16)
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
        .onChange(of: hasRoomChoice, initial: true) { hints.roomChoice(hasRoomChoice) }
        .onChange(of: state.tab) { _, tab in
            switch tab {
            case .moments: hints.done(MomentsHint())
            case .shop: hints.done(ShopHint())
            case .world: break
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                state.refresh()
                scene?.appOpened()
                Task {
                    await DrawingSync.requestPushes(asking: false)
                    await session?.drawingSync?.fetchLatest()
                    await session?.drawingSync?.registerPushTokens()
                    await session?.inbox.refreshCount()
                    await photoSync?.receive()
                }
                session?.followInbox(true)
                refreshRooms()
                if !launching { reportOpened(state.room) }
            case .background:
                state.didEnterBackground()
                session?.followInbox(false)
                reportedRooms = []
            default: break
            }
        }
        .sheet(isPresented: $state.showsUs) {
            UsView(state: state)
                .usSheet()
                // Settings opens from Us, so it is presented over the Us sheet.
                .sheet(isPresented: $state.showsSettings) {
                    SettingsView(state: state) {
                        scene?.stop()
                        HomeState.eraseAll()
                        state = HomeState()
                    }
                    .presentationBackground(Ink.sheet)
                    .presentationDragIndicator(.visible)
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
    private var photoSync: PhotoSync? {
        session?.photoSync(moments: state.moments, partner: state.partners.1)
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

/// Switches between Mochi's rooms and plays all her animations in turn, naming each as it plays.
private struct RoomControls: View {
    let state: HomeState
    let showcase: String?
    var select: (RoomKind) -> Void
    var playAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // One room has no switch: its name would be the only choice.
            if state.rooms.variant.hasRoomChoice {
                roomSwitch
            }

            Spacer(minLength: 0)

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

/// Dark amber vignette with drifting bokeh, standing in for the depth-of-field blur of the reference.
private struct WarmBackdrop: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0xF4BF7E), Color(hex: 0xB36E3A), Color(hex: 0x4A2C1B), Color(hex: 0x24150D)],
                center: UnitPoint(x: 0.5, y: 0.48),
                startRadius: 10,
                endRadius: 520
            )
            TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { context in
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
