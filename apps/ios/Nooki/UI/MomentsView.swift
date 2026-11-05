import PhotosUI
import SwiftUI
import UIKit

// MARK: - Moments

/// The couple's photo diary, and their notes and doodles pinned on the board in Mochi's desk room.
struct MomentsView: View {
    @Bindable var state: HomeState

    @State private var pick: PhotosPickerItem?
    @State private var draft: Draft?
    @State private var showsPicker = false
    @State private var showsHistory = false
    /// The open photo, from the feed or the board.
    @State private var viewing: PinRoute?
    /// Just added and still a milky blank until the compose sheet is gone.
    @State private var undeveloped: Set<UUID> = []
    @State private var feedWidth: CGFloat = 0
    @Namespace private var zoom

    private let hMargin: CGFloat = 16
    /// Same tab bar clearance as the shop.
    private let bottomInset: CGFloat = 134
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
                .padding(.bottom, bottomInset)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        WallStrip(store: store)
                        feed
                    }
                    .padding(.horizontal, hMargin)
                    .padding(.top, 4)
                    .padding(.bottom, bottomInset)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $pick, matching: .images)
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
                    if state.addMoment(draft.image, caption: caption), let added = store.moments.first {
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
                    MomentPrint(moment: moment, store: store, width: width, undeveloped: undeveloped.contains(moment.id))
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
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .glass(.capsule)
                    .padding(.bottom, 110)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Moments")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Ink.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)

                Spacer(minLength: 0)

                if state.momentsMode == .board, !notes.isEmpty {
                    Button { showsHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glass(.circle, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All notes")
                }

                Group {
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
                    } else {
                        Button { showsPicker = true } label: { plus }
                            .buttonStyle(.plain)
                    }
                }
                .accessibilityLabel(state.momentsMode == .board ? "Add a note" : "Add a moment")
            }
            .frame(height: 48)

            ModePicker(mode: $state.momentsMode)
        }
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(.honeyGradient))
            .shadow(color: Color.honeyDeep.opacity(0.4), radius: 8, y: 3)
    }
}

/// Photos as a feed, or the board in Mochi's desk room; styled like the World tab's room switcher.
private struct ModePicker: View {
    @Binding var mode: MomentsMode

    var body: some View {
        HStack(spacing: 2) {
            item(.photos, "Photos", "photo.on.rectangle")
            item(.board, "Board", "pin")
        }
        .padding(3)
        .glass(.capsule)
    }

    private func item(_ value: MomentsMode, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { mode = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(mode == value ? 0.96 : 0.6))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(mode == value ? Color.honey.opacity(0.45) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

// MARK: - Notes history

/// Every note and doodle the couple has left, by month, newest first; the board only has room for the latest few.
private struct NotesHistory: View {
    let state: HomeState

    @Environment(\.dismiss) private var dismiss
    @State private var opened: PinRoute?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var months: [(title: String, notes: [Note])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: state.notes.notes) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted(by: >).map { start in
            (start.formatted(.dateTime.month(.wide).year()), groups[start] ?? [])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Ink.primary)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.12), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")

                    VStack(alignment: .leading, spacing: 1) {
                        Text("All notes")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Ink.primary)
                        Text("\(state.notes.notes.count) \(state.notes.notes.count == 1 ? "note" : "notes")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .padding(.top, 22)

                ForEach(months, id: \.title) { month in
                    Text(month.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(month.notes) { note in
                            Button { opened = PinRoute(id: note.id) } label: {
                                NoteCard(note: note)
                                    .rotationEffect(note.id.polaroidTilt)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $opened) { route in NoteSheet(state: state, id: route.id) }
        .usSheet()
    }
}

/// A note as a small square of its paper: the text or doodle, and who left it; the same grain and shadow as the prints.
private struct NoteCard: View {
    let note: Note

    @State private var doodle: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background { PaperSheet(color: Color(hex: note.paper.hex)) }
            .overlay {
                if let doodle {
                    Image(uiImage: doodle).resizable().scaledToFit().padding(12)
                } else if note.doodle == nil {
                    Text(note.text)
                        .font(.custom("Noteworthy-Bold", size: 18))
                        .foregroundStyle(Color(hex: 0x5B3A28))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .padding(14)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("— \(note.author)")
                    .font(.custom("Noteworthy-Bold", size: 13))
                    .foregroundStyle(Color(hex: 0x5B3A28).opacity(0.7))
                    .padding(8)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.24), radius: 8, y: 6)
            .task(id: note.id) {
                guard let url = NoteStore.doodleURL(for: note) else { return }
                doodle = await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: 400) }.value
            }
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
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                Text("Add a photo of the two of you. It goes up on Mochi's wall as a little polaroid.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    Text("Add a photo")
                    Text("+10")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.white.opacity(0.22), in: .capsule)
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(.honeyGradient))
                .shadow(color: Color.honeyDeep.opacity(0.4), radius: 10, y: 4)
            }
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
                .overlay(Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Color(hex: 0xC99A6B)))
                .frame(width: 92, height: 92)
            Spacer().frame(height: 22)
        }
        .padding(7)
        .background { PaperSheet() }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.24), radius: 8, y: 6)
    }
}

// MARK: - Cards

/// A moment as a print: the graded photo in its polaroid, a heart if the other one loved it, and washi tape on the
/// ones hanging in Mochi's room.
struct MomentPrint: View {
    let moment: Moment
    let store: MomentStore
    let width: CGFloat
    var undeveloped = false
    var maxPixels = 512
    var captionEditor: Binding<String>?
    var captionFocus: FocusState<Bool>.Binding?

    var body: some View {
        Polaroid(width: width, caption: moment.caption, byline: moment.byline, undeveloped: undeveloped,
                 captionEditor: captionEditor, captionFocus: captionFocus) {
            MomentPhoto(store: store, moment: moment, maxPixels: maxPixels, film: true)
        }
        .overlay(alignment: .topTrailing) {
            if moment.loved {
                Image(systemName: "heart.fill")
                    .font(.system(size: max(11, width * 0.065), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: max(24, width * 0.14), height: max(24, width * 0.14))
                    .background(Color.blushPink, in: .circle)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(width * 0.09)
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
        HStack(spacing: 10) {
            Image(systemName: "house.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.honey)
            Text("On Mochi's wall")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
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
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Ink.hairline, lineWidth: 0.5))
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

// MARK: - Compose

struct ComposeSheet: View {
    let image: UIImage
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var film: UIImage?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("New moment")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                Image(uiImage: film ?? image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 220)
                    .clipped()
                TextField("", text: $caption, prompt: Text("Write a little note…").foregroundStyle(Color(hex: 0xB8957A)))
                    .font(.custom("Noteworthy-Bold", size: 17))
                    .foregroundStyle(PolaroidPaper.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .frame(width: 220)
                    .onChange(of: caption) { _, text in
                        if text.count > 40 { caption = String(text.prefix(40)) }
                    }
            }
            .padding(12)
            .padding(.bottom, 14)
            .background { PaperSheet() }
            .compositingGroup()
            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            .rotationEffect(.degrees(-2))

            Spacer(minLength: 0)

            Button {
                onSave(caption.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } label: {
                Text("Add to Moments · +10")
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(.honeyGradient))
                    .shadow(color: Color.honeyDeep.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .task {
            let image = image
            film = await Task.detached(priority: .userInitiated) { InstantFilm.develop(image) }.value
        }
        .usSheet()
    }
}

// MARK: - Viewer

/// One photo full screen, zoomed out of its print: the polaroid straightened, its caption editable on the strip, and
/// love, pin, share and delete around it.
private struct MomentViewer: View {
    let state: HomeState
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var confirmDelete = false
    @State private var polaroid: Image?
    @FocusState private var editing: Bool

    private var store: MomentStore { state.moments }
    private var moment: Moment? { store.moments.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            if let moment {
                topBar(moment)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                GeometryReader { geo in
                    MomentPrint(moment: moment, store: store, width: min(geo.size.width - 40, 520),
                                maxPixels: MomentStore.storedPixels, captionEditor: $caption, captionFocus: $editing)
                        .rotationEffect(.degrees(editing ? 0 : -1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    action(moment.loved ? "Loved" : "Love", symbol: moment.loved ? "heart.fill" : "heart",
                           tint: Color.blushPink, active: moment.loved) { store.toggleLove(moment) }
                    action(moment.pinned ? "On the wall" : "Pin to wall", symbol: moment.pinned ? "pin.fill" : "pin",
                           tint: Color.honey, active: moment.pinned) { store.togglePin(moment) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .background(Ink.sheet.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: moment)
        .animation(.snappy(duration: 0.25), value: editing)
        .onAppear { caption = moment?.caption ?? "" }
        .onChange(of: caption) { _, text in
            if text.count > 40 { caption = String(text.prefix(40)) }
        }
        .onChange(of: editing) { _, now in if !now { saveCaption() } }
        .onDisappear(perform: saveCaption)
        .task(id: moment?.caption) { polaroid = await renderPolaroid() }
        .confirmationDialog("Delete this moment?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let moment { store.delete(moment) }
                dismiss()
            }
        }
    }

    private func topBar(_ moment: Moment) -> some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer(minLength: 0)

            Menu {
                ShareLink(item: MomentStore.imageURL(for: moment)) {
                    Label("Share photo", systemImage: "photo")
                }
                if let polaroid {
                    ShareLink(item: polaroid, preview: SharePreview(moment.caption.isEmpty ? "Moment" : moment.caption,
                                                                    image: polaroid)) {
                        Label("Share as polaroid", systemImage: "rectangle.portrait.bottomhalf.filled")
                    }
                }
                Button { editing = true } label: { Label("Edit caption", systemImage: "pencil") }
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: .circle)
            }
            .accessibilityLabel("Share and more")
        }
    }

    private func saveCaption() {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let moment, text != moment.caption else { return }
        store.setCaption(text, of: moment)
    }

    /// The print as an image to share: graded photo, frame, caption and byline, without the tilt and shadow.
    private func renderPolaroid() async -> Image? {
        guard let moment, let photo = await store.filmPrint(for: moment, maxPixels: 1024) else { return nil }
        let renderer = ImageRenderer(content: Polaroid(width: 540, caption: moment.caption, byline: moment.byline,
                                                       lifted: false) {
            Image(uiImage: photo).resizable().scaledToFill()
        })
        renderer.scale = 2
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    private func action(_ title: String, symbol: String, tint: Color, active: Bool,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(active ? tint.opacity(0.22) : .white.opacity(0.1), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
