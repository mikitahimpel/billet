import SwiftUI
import Design
import Transport
import Wire

/// Drawing on what looks like the partner's lock screen: their wallpaper, the big clock and date, and a glass
/// toolbar at the bottom. When both have it open, each sees the other's ink appear as it is drawn.
struct LockCanvasView: View {
    let state: HomeState
    let api: APIClient?
    @State var model: DrawModel

    @Environment(\.dismiss) private var dismiss
    @State private var choosingInk = false
    @State private var canvasSize = CGSize.zero
    @State private var sent = 0
    @State private var coinsShown: CoinsAsk?
    /// The coin packs the Store sheet sells, from the Home screen that presented this canvas.
    var coinPacks: CoinPacksModel?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LockWallpaperView(wallpaper: model.wallpaper, photo: model.photo)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                // Under the chrome: a surface over the buttons takes their taps, which is how Close once did nothing.
                drawingSurface(size: geometry.size)

                VStack(spacing: 0) {
                    topBar
                    clock
                        .allowsHitTesting(false)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.l)

                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if choosingInk { inkPalette.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    toolbar
                    homeIndicator
                }
                .padding(.horizontal, Space.l)
            }
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, size in canvasSize = size }
        }
        .statusBarHidden()
        .animation(.spring(duration: 0.3), value: choosingInk)
        .animation(.easeInOut(duration: 0.25), value: model.isPartnerDrawing)
        .sensoryFeedback(.success, trigger: sent)
        .sensoryFeedback(.selection, trigger: model.ink)
        .onAppear { model.appeared() }
        // The partner's drawings arrive as notifications; asked here, where it is plain why.
        .task { await DrawingSync.requestPushes(asking: true) }
        .onDisappear { model.disappeared() }
        // Over the canvas: an ink bought here plays its moment and Undo where it was tapped.
        .overlay { PurchaseMoment(state: state) }
        // The Store opens over the canvas: Home's own sheet would wait under this cover.
        .onChange(of: state.shop.coinsAsk) { _, ask in coinsShown = ask }
        .sheet(item: $coinsShown, onDismiss: { state.shop.coinsAsk = nil }) { ask in
            CoinsSheet(state: state, packs: coinPacks, ask: ask)
        }
    }

    // MARK: The lock screen

    private var topBar: some View {
        HStack(alignment: .center) {
            GlassIconButton(symbol: "xmark", label: "Close") { dismiss() }
                .accessibilityIdentifier("drawClose")

            Spacer()

            VStack(spacing: 3) {
                Text(model.partnerName)
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                if model.isPartnerDrawing {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x41D37E)).frame(width: 7, height: 7)
                        Text("\(model.partnerName) is drawing…")
                            .font(.nookiMicro)
                            .foregroundStyle(Ink.primary)
                    }
                    .transition(.opacity)
                    .accessibilityIdentifier("partnerDrawing")
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)

            Spacer()

            wallpaperMenu
        }
        .padding(.top, Space.s)
        // Swiping down from the top bar dismisses; the canvas below keeps every other drag for ink.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 80, abs(value.translation.width) < value.translation.height {
                        dismiss()
                    }
                }
        )
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: -6) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.nookiClockDate)
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.nookiClock)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        }
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
    }

    private var homeIndicator: some View {
        Capsule()
            .fill(.white.opacity(0.7))
            .frame(width: 134, height: 5)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    private var wallpaperMenu: some View {
        Menu {
            ForEach(LockWallpaper.allCases) { wallpaper in
                Button(wallpaper.title) {
                    model.photo = nil
                    model.wallpaper = wallpaper
                }
            }
            if !state.moments.moments.isEmpty {
                Menu("From Moments") {
                    ForEach(state.moments.moments.prefix(12)) { moment in
                        Button(moment.caption.isEmpty ? moment.date.formatted(date: .abbreviated, time: .omitted)
                                                      : moment.caption) {
                            Task { model.photo = await state.moments.thumbnail(for: moment, maxPixels: 1600) }
                        }
                    }
                }
            }
        } label: {
            GlassSymbol(name: "photo.on.rectangle")
                .frame(width: Size.control, height: Size.control)
                .glass(.circle, tint: Ink.glassTint, clear: true, interactive: true)
                .contentShape(.circle)
        }
        .accessibilityLabel("Wallpaper")
        .accessibilityIdentifier("drawWallpaper")
    }

    // MARK: Drawing

    private func drawingSurface(size: CGSize) -> some View {
        let width = max(size.width, 1)
        return InkLayer(strokes: model.partnerStrokes + model.strokes + (model.current.map { [$0] } ?? []))
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if choosingInk { choosingInk = false }
                        model.touch(Point(x: value.location.x / width, y: value.location.y / width))
                    }
                    .onEnded { _ in model.lift() }
            )
            .accessibilityLabel("Drawing canvas")
            .accessibilityIdentifier("drawCanvas")
    }

    // MARK: Tools

    private var toolbar: some View {
        GlassGroup(spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Button { choosingInk.toggle() } label: {
                    Circle()
                        .fill(model.ink.color(onDark: true))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .frame(width: 26, height: 26)
                        .frame(width: Size.control, height: Size.control)
                        .contentShape(.circle)
                }
                .accessibilityLabel("Ink, \(model.ink.name)")
                .accessibilityIdentifier("drawInk")

                tool("arrow.uturn.backward", label: "Undo", id: "drawUndo", enabled: model.canUndo) { model.undo() }
                tool("eraser.fill", label: "Eraser", id: "drawEraser", selected: model.tool == .eraser) {
                    model.tool = model.tool == .eraser ? .pen : .eraser
                }
                tool("trash", label: "Clear", id: "drawClear", enabled: !model.isEmpty) { model.clear() }

                Spacer(minLength: Space.xs)

                Button { send() } label: {
                    if model.sendState == .sending {
                        ProgressView().tint(Ink.heroInk)
                    } else {
                        Image(systemName: model.sendState == .failed ? "arrow.clockwise" : "paperplane.fill")
                            .font(.body.weight(.bold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .disabled(model.isEmpty || model.sendState == .sending)
                .accessibilityLabel(model.sendState == .failed ? "Try sending again" : "Send")
                .accessibilityIdentifier("drawSend")
            }
            .buttonStyle(.plain)
            .padding(Space.xs)
            .warmGlass(Capsule(), interactive: true)
        }
    }

    private func tool(_ symbol: String, label: String, id: String, enabled: Bool = true, selected: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .imageScale(.large)
                .foregroundStyle(selected ? Ink.heroInk : Ink.primary)
                .frame(width: Size.control, height: Size.control)
                .background(Circle().fill(selected ? Color.honey : .clear))
                .contentShape(.circle)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var inkPalette: some View {
        InkPalette(state: state, selection: $model.ink, onDark: true, label: .white, closesForStore: false) {
            model.tool = .pen
            choosingInk = false
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .warmGlass(Capsule())
    }

    // MARK: Actions

    private func send() {
        Task {
            if await model.send(api: api, canvas: canvasSize, state: state) {
                sent += 1
                state.tab = .moments
                dismiss()
            }
        }
    }
}
