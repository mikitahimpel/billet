import SwiftUI
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
    @State private var lockedInk: DrawInk?
    @State private var canvasSize = CGSize.zero
    @State private var sent = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LockWallpaperView(wallpaper: model.wallpaper, photo: model.photo)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    topBar
                    clock
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .allowsHitTesting(true)

                drawingSurface(size: geometry.size)

                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if choosingInk { inkPalette.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    toolbar
                    homeIndicator
                }
                .padding(.horizontal, 16)
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
        .alert(item: $lockedInk) { ink in
            Alert(
                title: Text("\(ink.name) ink"),
                message: Text("\(ink.price) coins in the Shop."),
                primaryButton: .default(Text("Open Shop")) { openShop() },
                secondaryButton: .cancel())
        }
    }

    // MARK: The lock screen

    private var topBar: some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glass(.circle, interactive: true)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("drawClose")

            Spacer()

            VStack(spacing: 3) {
                Text(model.partnerName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                if model.isPartnerDrawing {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x41D37E)).frame(width: 7, height: 7)
                        Text("\(model.partnerName) is drawing…")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .transition(.opacity)
                    .accessibilityIdentifier("partnerDrawing")
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)

            Spacer()

            wallpaperMenu
        }
        .padding(.top, 8)
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: -6) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 104, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        }
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
    }

    private var homeIndicator: some View {
        Capsule()
            .fill(.white.opacity(0.85))
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
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glass(.circle, interactive: true)
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
        GlassGroup(spacing: 8) {
            HStack(spacing: 6) {
                Button { choosingInk.toggle() } label: {
                    Circle()
                        .fill(model.ink.color)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .frame(width: 26, height: 26)
                        .shadow(color: model.ink.color.opacity(0.6), radius: 5)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Ink, \(model.ink.name)")
                .accessibilityIdentifier("drawInk")

                tool("arrow.uturn.backward", label: "Undo", id: "drawUndo", enabled: model.canUndo) { model.undo() }
                tool("eraser.fill", label: "Eraser", id: "drawEraser", selected: model.tool == .eraser) {
                    model.tool = model.tool == .eraser ? .pen : .eraser
                }
                tool("trash", label: "Clear", id: "drawClear", enabled: !model.isEmpty) { model.clear() }

                Spacer(minLength: 4)

                Button { send() } label: {
                    Group {
                        if model.sendState == .sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: model.sendState == .failed ? "arrow.clockwise" : "paperplane.fill")
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 44)
                    .background(Capsule().fill(.honeyGradient))
                }
                .disabled(model.isEmpty || model.sendState == .sending)
                .opacity(model.isEmpty ? 0.5 : 1)
                .accessibilityLabel(model.sendState == .failed ? "Try sending again" : "Send")
                .accessibilityIdentifier("drawSend")
            }
            .buttonStyle(.plain)
            .padding(6)
            .warmGlass(Capsule(), interactive: true)
        }
    }

    private func tool(_ symbol: String, label: String, id: String, enabled: Bool = true, selected: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? Color(hex: 0x3A2114) : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(selected ? Color.white.opacity(0.9) : .clear))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var inkPalette: some View {
        HStack(spacing: 10) {
            ForEach(DrawInks.all) { ink in
                let owned = ink.isOwned(state.shop.owned)
                Button {
                    if owned {
                        model.ink = ink
                        model.tool = .pen
                        choosingInk = false
                    } else {
                        lockedInk = ink
                    }
                } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(ink.color)
                            .overlay(Circle().strokeBorder(.white.opacity(model.ink == ink ? 1 : 0.5),
                                                           lineWidth: model.ink == ink ? 3 : 1))
                            .overlay {
                                if !owned {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 1)
                                }
                            }
                            .frame(width: 30, height: 30)
                            .opacity(owned ? 1 : 0.7)
                        if !owned {
                            HStack(spacing: 2) {
                                CoinIcon(size: 9)
                                Text("\(ink.price)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .frame(minWidth: 34, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(owned ? "\(ink.name) ink" : "\(ink.name) ink, locked, \(ink.price) coins")
                .accessibilityIdentifier("ink-\(ink.id)")
            }
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

    private func openShop() {
        state.tab = .shop
        dismiss()
    }
}
