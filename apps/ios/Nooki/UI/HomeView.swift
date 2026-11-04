import SwiftUI

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
    @Environment(ServerSession.self) private var session: ServerSession?
    @AppStorage(AppSettings.brainCardKey) private var brainCard = false

    /// The board room behind the Moments tab, when it shows the board rather than the feed.
    private var showsBoard: Bool { state.tab == .moments && state.momentsMode == .board }
    /// The World tab and the board show a room; the others get their own screens over the backdrop.
    private var showsRoom: Bool { state.tab == .world || showsBoard }

    var body: some View {
        ZStack {
            WarmBackdrop()

            if let scene {
                DioramaView(scene: scene, paused: !showsRoom, petPulse: state.petPulse) {
                    withAnimation(.spring(duration: 0.4)) { state.pet() }
                }
                .opacity(showsRoom ? 1 : 0)
                .allowsHitTesting(showsRoom)
                .ignoresSafeArea()
            }

            if state.tab == .shop {
                // The scroll view runs under the tab bar and keeps its own 16pt margins.
                ShopView(state: state)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            } else if state.tab == .moments {
                MomentsView(state: state)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            } else if state.tab == .us {
                UsView(state: state)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            } else {
                VStack(spacing: 16) {
                    CoupleRow(state: state)
                    RoomControls(state: state, showcase: showcase, select: select) { scene?.playAll() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 82)
                .transition(.opacity.combined(with: .offset(y: 12)))
            }

            VStack {
                Spacer(minLength: 0)
                TabBar(state: state)
                    .padding(.horizontal, 16)
            }
        }
        // Bottom left, so it stays clear of the "+" in the right corner.
        .overlay(alignment: .bottomLeading) {
            if state.tab == .world {
                PetButton(state: state) { scene?.playAll() }
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
        .task { await lift() }
        .task {
            guard home == nil else { return }
            let room = DioramaScene()
            home = room
            room.setPolaroids(await state.moments.thumbnails(for: state.moments.pinned, maxPixels: MomentStore.wallPixels))
        }
        .task(id: state.moments.pinned) {
            let images = await state.moments.thumbnails(for: state.moments.pinned, maxPixels: MomentStore.wallPixels)
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
        .onChange(of: state.room) { showcase = nil }
        // Pets from the widget and the control reach Mochi when the app comes back.
        .onChange(of: state.petPulse) { scene?.purr() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                state.refresh()
                scene?.appOpened()
            case .background: state.didEnterBackground()
            default: break
            }
        }
        .sheet(isPresented: $state.showsSettings) {
            SettingsView(state: state) {
                scene?.stop()
                HomeState.eraseAll()
                state = HomeState()
            }
            .presentationBackground(Ink.sheet)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $state.composingNote) { mode in
            NoteComposer(state: state, mode: mode)
        }
        .fullScreenCover(isPresented: $state.drawing) {
            LockCanvasView(
                state: state, api: session?.api,
                model: DrawModel(room: session?.liveRoom(), partnerName: state.otherPartner))
        }
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
        if UserDefaults.standard.string(forKey: "room") == "city" { select(.city) }
    }

    private func select(_ room: RoomKind) {
        guard room != state.room else { return }
        scene?.stop()
        if room == .city {
            // After the tap has drawn; until then the home room stays on screen.
            Task { if state.room == .city, city == nil { city = CityRoomScene() } }
        } else {
            city = nil
        }
        withAnimation(.snappy(duration: 0.25)) { state.room = room }
    }

    private var scene: CatRoom? {
        guard let home else { return nil }
        if showsBoard, let board { return board }
        let room: CatRoom = state.room == .city ? city ?? home : home
        room.onShowcase = { label in withAnimation(.snappy(duration: 0.25)) { showcase = label } }
        return room
    }

    /// The ids of the newest notes on the board; a new set rebuilds their faces.
    private var boardKey: [UUID] {
        state.notes.notes.prefix(BoardRoomScene.slots).map(\.id)
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
            HStack(spacing: 2) {
                ForEach(RoomKind.allCases, id: \.self) { room in
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
