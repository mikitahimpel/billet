import PetScene
import PhotosUI
import SwiftUI
import Design
import UIKit
import Wire

// MARK: - Moments

/// The couple's photo diary, and their notes and doodles pinned on the board in Mochi's desk room.
struct MomentsView: View {
    @Bindable var state: HomeState

    @State private var pick: PhotosPickerItem?
    @State private var draft: Draft?
    @State private var showsHistory = false
    /// The open photo, from the feed or the board.
    @State private var viewing: PinRoute?
    /// Just added and still a milky blank until the compose sheet is gone.
    @State private var undeveloped: Set<UUID> = []
    @State private var feedWidth: CGFloat = 0
    /// Where the feed is scrolled to; a perf run moves it (`NookiPerf.scrolls`).
    @State private var position = ScrollPosition(edge: .top)
    @Namespace private var zoom

    private let hMargin: CGFloat = 16
    private let columnGap: CGFloat = 14

    private var store: MomentStore { state.moments }
    private var notes: [Note] { state.notes.notes }

    var body: some View {
        Group {
            if state.momentsMode == .board {
                boardOverlay
            } else if store.moments.isEmpty {
                VStack(spacing: 0) {
                    header.padding(.horizontal, hMargin)
                    Spacer(minLength: 0)
                    EmptyMoments(pick: $pick)
                        .padding(.horizontal, 32)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
                .padding(.bottom, Space.l)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        WallStrip(store: store)
                        feed
                    }
                    .padding(.horizontal, hMargin)
                    .padding(.top, 4)
                    .padding(.bottom, Space.l)
                }
                .scrollIndicators(.hidden)
                .scrollPosition($position)
                .softScrollEdges()
                .onAppear {
                    guard ScenePerf.isOn else { return }
                    NookiPerf.scrolls[.moments] = { position.scrollTo(y: $0) }
                }
                .onDisappear { NookiPerf.scrolls[.moments] = nil }
            }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let image = await item.loadImage(maxPixels: MomentStore.storedPixels) {
                    draft = Draft(image: image)
                }
                pick = nil
            }
        }
        .sheet(item: $draft, onDismiss: develop) { draft in
            ComposeSheet(image: draft.image) { caption in
                withAnimation(.spring(duration: 0.4)) {
                    if state.journal.addMoment(draft.image, caption: caption, shares: true), let added = store.moments.first {
                        undeveloped.insert(added.id)
                    }
                }
            }
        }
        .sheet(isPresented: $showsHistory) {
            NotesHistory(state: state)
        }
        .sheet(item: openedNote) { route in
            NoteSheet(state: state, id: route.id)
        }
        .fullScreenCover(item: openedPhoto) { route in
            MomentViewer(state: state, id: route.id)
                .navigationTransition(.zoom(sourceID: route.id, in: zoom))
        }
    }

    /// A board card that is a note opens as a sheet; a photo opens full screen, like one tapped in the feed.
    private var openedNote: Binding<PinRoute?> {
        Binding {
            state.openedPin.flatMap { route in notes.contains { $0.id == route.id } ? route : nil }
        } set: { state.openedPin = $0 }
    }

    private var openedPhoto: Binding<PinRoute?> {
        Binding {
            viewing ?? state.openedPin.flatMap { route in store.moments.contains { $0.id == route.id } ? route : nil }
        } set: { route in
            viewing = route
            if route == nil { state.openedPin = nil }
        }
    }

    /// The new print develops once the compose sheet is out of the way.
    private func develop() {
        guard !undeveloped.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            undeveloped.removeAll()
        }
    }

    /// Two loose columns of prints, the right one dropped a little and each print overlapping the one above.
    private var feed: some View {
        let width = max(0, (feedWidth - columnGap) / 2)
        return HStack(alignment: .top, spacing: columnGap) {
            column(0, width: width)
            column(1, width: width).padding(.top, width * 0.3)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { feedWidth = $0 }
    }

    private func column(_ parity: Int, width: CGFloat) -> some View {
        let moments = store.moments.enumerated().filter { $0.offset % 2 == parity }.map(\.element)
        return LazyVStack(spacing: -width * 0.05) {
            ForEach(moments) { moment in
                Button { viewing = PinRoute(id: moment.id) } label: {
                    MomentPrint(moment: moment, store: store, profile: state.profile, width: width, undeveloped: undeveloped.contains(moment.id))
                        .rotationEffect(moment.id.polaroidTilt)
                        .padding(.vertical, width * 0.04)
                }
                .buttonStyle(PressScaleStyle())
                .matchedTransitionSource(id: moment.id, in: zoom)
            }
        }
    }

    /// The board room shows underneath; only the header and, on an empty board, a hint sit over it.
    private var boardOverlay: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, hMargin)
                .padding(.top, 4)
            Spacer(minLength: 0)
            if notes.isEmpty, store.pinned.isEmpty {
                Text("Leave a note or doodle for the board")
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .glass(.capsule)
                    .padding(.bottom, Space.l)
            }
        }
    }

    private var subtitle: String? {
        if state.momentsMode == .board {
            let count = min(notes.count + store.pinned.count, BoardRoomScene.slots)
            return count == 0 ? nil : "\(count) on the board"
        }
        return store.moments.isEmpty ? nil : "\(store.moments.count) \(store.moments.count == 1 ? "photo" : "photos")"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                titleMenu
                if let subtitle {
                    Text(subtitle)
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.secondary)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)

            Spacer(minLength: 0)

            if state.momentsMode == .board, !notes.isEmpty {
                GlassIconButton(symbol: "clock.arrow.circlepath", label: "All notes") { showsHistory = true }
            }

            // Photos are added from the tab bar's +; the board keeps its own for doodles, which the + doesn't offer.
            if state.momentsMode == .board {
                Menu {
                    Button { state.composingNote = .write } label: {
                        Label("Note", systemImage: "note.text")
                        Text("+5")
                    }
                    Button { state.composingNote = .draw } label: {
                        Label("Doodle", systemImage: "scribble")
                        Text("+5")
                    }
                } label: { plus }
                .accessibilityLabel("Add a note")
            }
        }
        .frame(minHeight: Size.control)
    }

    /// The large title is the switch between the photo feed and the board, as in Photos and Notes.
    private var titleMenu: some View {
        Menu {
            Picker("Show", selection: $state.momentsMode.animation(.snappy(duration: 0.25))) {
                Label("Photos", systemImage: "photo.on.rectangle").tag(MomentsMode.photos)
                Label("Board", systemImage: "square.grid.2x2").tag(MomentsMode.board)
            }
        } label: {
            HStack(spacing: Space.xs + 2) {
                Text("Moments")
                    .font(.nookiLargeTitle)
                    .foregroundStyle(Ink.primary)
                Image(systemName: "chevron.down")
                    .font(.nookiCallout.weight(.bold))
                    .foregroundStyle(Ink.secondary)
            }
            .contentShape(.rect)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Moments")
        .accessibilityValue(state.momentsMode == .board ? "Board" : "Photos")
        .accessibilityHint("Switches between Photos and Board")
        .accessibilityIdentifier("momentsMode")
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.body.weight(.bold))
            .foregroundStyle(Ink.heroInk)
            .frame(width: Size.control, height: Size.control)
            .background(Color.honey, in: .circle)
    }
}

private struct Draft: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Empty state

private struct EmptyMoments: View {
    @Binding var pick: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                BlankPolaroid(symbol: "heart.fill").rotationEffect(.degrees(-10)).offset(x: -46, y: 6)
                BlankPolaroid(symbol: "camera.fill").rotationEffect(.degrees(8)).offset(x: 46, y: 10)
                BlankPolaroid(symbol: "sparkles").rotationEffect(.degrees(-2)).offset(y: -8)
            }
            .frame(height: 170)

            VStack(spacing: 8) {
                Text("Your first moment")
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.primary)
                Text("Add a photo of the two of you. It goes up on \(CatProfile.name())'s wall as a little polaroid.")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    Text("Add a photo")
                    Text("+10")
                        .font(.nookiMicro)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Ink.heroInk.opacity(0.12), in: .capsule)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
        }
    }
}

private struct BlankPolaroid: View {
    let symbol: String

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(hex: 0xF0DCC0), Color(hex: 0xE2C29C)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: symbol).font(.title2).foregroundStyle(Color(hex: 0xC99A6B)))
                .frame(width: 92, height: 92)
            Spacer().frame(height: 22)
        }
        .padding(7)
        .background { PaperSheet(lift: PaperSheet.Lift()) }
    }
}

// MARK: - Cards

/// A moment as a print: the graded photo in its polaroid, the partner's reaction to it (or a heart on one kept only
/// here), and washi tape on the ones hanging in Mochi's room.
struct MomentPrint: View {
    let moment: Moment
    let store: MomentStore
    let profile: CoupleStore
    let width: CGFloat
    var undeveloped = false
    var maxPixels = 512
    var captionEditor: Binding<String>?
    var captionFocus: FocusState<Bool>.Binding?
    @Environment(ServerSession.self) private var session: ServerSession?

    /// Only one side has a reaction per photo: the partner's on this user's, this user's on the partner's.
    private var reaction: PhotoReaction? {
        guard let note = moment.noteID, let reactions = session?.reactions else { return nil }
        return reactions.theirs(note) ?? reactions.mine(note)
    }

    var body: some View {
        Polaroid(width: width, caption: moment.caption, byline: profile.byline(of: moment), undeveloped: undeveloped,
                 captionEditor: captionEditor, captionFocus: captionFocus) {
            MomentPhoto(store: store, moment: moment, maxPixels: maxPixels, film: true)
        }
        .overlay(alignment: .topTrailing) {
            if let reaction {
                Text(reaction.emoji)
                    .font(.system(size: max(13, width * 0.08)))
                    .frame(width: max(28, width * 0.16), height: max(28, width * 0.16))
                    .background(Ink.surface, in: .circle)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(width * 0.08)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Reacted \(reaction.label)")
            } else if moment.loved {
                Image(systemName: "heart.fill")
                    .font(.system(size: max(11, width * 0.065), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: max(24, width * 0.14), height: max(24, width * 0.14))
                    .background(Color.blushPink, in: .circle)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(width * 0.09)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if moment.unsent == true, session?.isPaired == true {
                UnsentMark(size: max(10, width * 0.05)).padding(width * 0.06)
            }
        }
        .overlay(alignment: .top) {
            if moment.pinned {
                WashiTape(tone: moment.id.tapeTone, width: width * 0.34)
                    .rotationEffect(.degrees(-4))
                    .offset(y: -width * 0.06)
            }
        }
    }
}

/// Pinned moments in wall order, so it's clear what Mochi's room shows.
private struct WallStrip: View {
    let store: MomentStore

    var body: some View {
        HStack(spacing: Space.s) {
            Label("On \(CatProfile.name())'s wall", systemImage: "house.fill")
                .font(.nookiCallout)
                .foregroundStyle(Ink.text)
                .labelStyle(.titleAndIcon)
                .tint(.honey)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<MomentStore.wallSlots, id: \.self) { slot in
                    let moment = slot < store.pinned.count ? store.pinned[slot] : nil
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: 0xE9D6BC))
                        .overlay {
                            if let moment { MomentPhoto(store: store, moment: moment, maxPixels: MomentStore.wallPixels) }
                        }
                        .clipShape(.rect(cornerRadius: 2))
                        .frame(width: 20, height: 20)
                        .padding(2)
                        .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 3))
                }
            }
        }
        .padding(.horizontal, Space.l)
        .frame(height: 50)
        .background(Ink.surface, in: .rect(cornerRadius: Radius.control, style: .continuous))
    }
}

/// A moment's photo at `maxPixels`, decoded off the main thread; blank until it arrives.
private struct MomentPhoto: View {
    let store: MomentStore
    let moment: Moment
    let maxPixels: Int
    /// With the instant-film grade, as on a polaroid.
    var film = false

    @State private var loaded: UIImage?

    private var cached: UIImage? {
        film ? store.cachedFilmPrint(for: moment, maxPixels: maxPixels) : store.cachedThumbnail(for: moment, maxPixels: maxPixels)
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image = cached ?? loaded {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .task(id: moment.file) {
                // A wall slot can switch moments; don't keep showing the previous photo meanwhile.
                loaded = nil
                loaded = film
                    ? await store.filmPrint(for: moment, maxPixels: maxPixels)
                    : await store.thumbnail(for: moment, maxPixels: maxPixels)
            }
    }
}

extension PhotosPickerItem {
    /// The picked photo decoded at `maxPixels` off the main thread, never as the full 12 MP bitmap.
    func loadImage(maxPixels: Int) async -> UIImage? {
        guard let data = try? await loadTransferable(type: Data.self) else { return nil }
        return await Task.detached(priority: .userInitiated) { Downsample.image(data: data, maxPixels: maxPixels) }.value
    }
}
