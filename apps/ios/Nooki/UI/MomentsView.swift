import DrawInterface
import MomentsInterface
import WidgetInterface
import WidgetUI
import PetScene
import PhotosUI
import ProfileInterface
import SwiftUI
import Design
import UIKit
import UsInterface
import Wire

// MARK: - Moments

struct MomentsView: View {
    @Bindable var state: HomeState

    @State private var pick: PhotosPickerItem?
    @State private var draft: Draft?
    @State private var viewing: PinRoute?
    /// Just added and still a milky blank until the compose sheet is gone.
    @State private var undeveloped: Set<UUID> = []
    @State private var feedWidth: CGFloat = 0

    private let columnGap: CGFloat = Space.m

    private var store: MomentStore { state.moments }
    private var notes: [Note] { state.notes.notes }

    var body: some View {
        Group {
            if state.momentsMode == .board {
                boardOverlay
            } else if store.moments.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    EmptyMoments(pick: $pick)
                        .padding(.horizontal, Space.xl)
                    Spacer(minLength: 0)
                }
                .tabContentInsets()
            } else {
                TabPage {
                    WallStrip(store: store, pick: $pick)
                    feed
                }
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
                withAnimation(Motion.spring(0.4)) {
                    if state.journal.addMoment(draft.image, caption: caption, shares: true), let added = store.moments.first {
                        undeveloped.insert(added.id)
                    }
                }
            }
        }
        .sheet(item: openedNote) { route in
            NoteSheet(state: state, id: route.id)
        }
        .fullScreenCover(item: openedPhoto) { route in
            // No zoom from the print: dismissing one shrinks the whole viewer, upright and with the screen's corners,
            // into the print's frame, which then snaps to the tilted print.
            MomentViewer(state: state, id: route.id)
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
                        .perfFlattened()
                        .rotationEffect(moment.id.polaroidTilt)
                        .padding(.vertical, width * 0.04)
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    /// The board room shows underneath; over it the history of notes at the top and, always, the way to add one at
    /// the foot, so it is plain where a note comes from.
    private var boardOverlay: some View {
        VStack(spacing: Space.m) {
            if !notes.isEmpty {
                BoardActions(state: state)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Space.l)
            }
            Spacer(minLength: 0)
            if notes.isEmpty, store.pinned.isEmpty {
                Text("The board is empty. Leave the first note.")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.glassGlyph)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.l)
            }
            HStack(spacing: GlassMetrics.gap) {
                BoardAddButton(title: "New note", symbol: "note.text", identifier: "boardNewNote") {
                    state.composingNote = .write
                }
                BoardAddButton(title: "Doodle", symbol: "scribble", identifier: "boardNewDoodle") {
                    state.composingNote = .draw
                }
            }
            .padding(.bottom, Space.l)
        }
        .tabContentInsets()
    }
}

private struct BoardAddButton: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.glassGlyph)
                .padding(.horizontal, Space.l)
                .frame(minHeight: Size.control)
                .glass(.capsule, role: .bar)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// All notes, at the top of the board.
struct BoardActions: View {
    let state: HomeState
    @State private var showsHistory = false

    var body: some View {
        GlassIconButton(symbol: "clock.arrow.circlepath", label: "All notes") { showsHistory = true }
            .sheet(isPresented: $showsHistory) {
                NotesHistory(state: state)
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
        VStack(spacing: Space.section) {
            ZStack {
                BlankPolaroid(symbol: "heart.fill").rotationEffect(.degrees(-10)).offset(x: -46, y: 6)
                BlankPolaroid(symbol: "camera.fill").rotationEffect(.degrees(8)).offset(x: 46, y: 10)
                BlankPolaroid(symbol: "sparkles").rotationEffect(.degrees(-2)).offset(y: -8)
            }
            .frame(height: 170)

            VStack(spacing: Space.s) {
                Text("Your first moment")
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.primary)
                Text("Add a photo of the two of you. It goes up on \(CatProfile.name())'s wall as a little polaroid.")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: Space.s) {
                    Image(systemName: "photo.badge.plus")
                    Text("Add a photo")
                    Text("+10")
                        .font(.ourioCaption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs / 2)
                        .background(Ink.heroInk.opacity(0.12), in: .capsule)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Space.xs)
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

struct MomentPrint: View {
    let moment: Moment
    let store: MomentStore
    let profile: CoupleStore
    let width: CGFloat
    var undeveloped = false
    var maxPixels = PrintSizes.feed
    var captionEditor: Binding<String>?
    var captionFocus: FocusState<Bool>.Binding?
    @Environment(ServerSession.self) private var session: ServerSession?

    /// Only one side has a reaction per photo: the partner's on this user's, this user's on the partner's.
    private var reaction: PhotoReaction? {
        guard let note = moment.noteID, let reactions = session?.reactions else { return nil }
        return reactions.theirs(note) ?? reactions.mine(note)
    }

    static func stampWidth(_ width: CGFloat) -> CGFloat { max(StampSize.small.width, width * 0.15) }

    var body: some View {
        Polaroid(width: width, caption: moment.caption, byline: profile.byline(of: moment), undeveloped: undeveloped,
                 captionLines: 2, markSpace: moment.noteID == nil ? 0 : Self.stampWidth(width) + width * 0.05,
                 captionEditor: captionEditor, captionFocus: captionFocus) {
            MomentPhoto(store: store, moment: moment, maxPixels: maxPixels, film: true)
        }
        .overlay(alignment: .topTrailing) {
            if let reaction {
                Text(reaction.emoji)
                    .font(.system(size: max(13, width * 0.08)))
                    .frame(width: max(28, width * 0.16), height: max(28, width * 0.16))
                    .background(Ink.surface, in: .circle)
                    .perfShadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(width * 0.08)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Reacted \(reaction.label)")
            } else if moment.loved {
                Image(systemName: "heart.fill")
                    .font(.system(size: max(11, width * 0.065), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: max(24, width * 0.14), height: max(24, width * 0.14))
                    .background(Color.blushPink, in: .circle)
                    .perfShadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(width * 0.09)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // A print that went between the phones carries a stamp cancelled on its day, as a sent note does.
            if moment.noteID != nil {
                PostageStamp(moment.id.stampArt, width: Self.stampWidth(width), postmark: moment.date)
                    .rotationEffect(.degrees(4))
                    .padding(width * 0.05)
                    .accessibilityHidden(true)
            } else if UnsentMark.shows(moment.unsent, paired: session?.isPaired == true) {
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

/// Pinned moments in wall order, so it's clear what Mochi's room shows: six small prints across the card, each
/// empty slot a well with the honey "+" of the bar's own button, and the same picker as a pill in the header.
private struct WallStrip: View {
    let store: MomentStore
    @Binding var pick: PhotosPickerItem?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.m) {
                CardHeader("On \(CatProfile.name())'s wall") {
                    RowIcon(symbol: "house.fill", size: Size.cardMark, style: .clay)
                } detail: {
                    Text(WallCopy.detail(pinned: store.pinned.count, slots: MomentStore.wallSlots))
                } trailing: {
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label("Add photo", systemImage: "plus")
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("wallAddPhoto")
                }
                HStack(spacing: Space.s) {
                    ForEach(0..<MomentStore.wallSlots, id: \.self) { slot in
                        let moment = slot < store.pinned.count ? store.pinned[slot] : nil
                        if let moment {
                            WallSlot(store: store, moment: moment).accessibilityHidden(true)
                        } else {
                            PhotosPicker(selection: $pick, matching: .images) {
                                EmptyWallSlot()
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel("Add a photo to the wall")
                        }
                    }
                }
            }
        }
    }
}

/// The wall card's line under its title.
enum WallCopy {
    static func detail(pinned: Int, slots: Int) -> String {
        if pinned == 0 { return "Empty · tap + to hang a photo" }
        if pinned >= slots { return "\(pinned) of \(slots) · full; a new pin swaps the oldest" }
        return "\(pinned) of \(slots) · tap + to hang one"
    }
}

private struct WallSlot: View {
    let store: MomentStore
    let moment: Moment

    var body: some View {
        PolaroidPaper.blank
            .aspectRatio(1, contentMode: .fit)
            .overlay { MomentPhoto(store: store, moment: moment, maxPixels: MomentStore.wallPixels) }
            .clipped()
            .padding(Space.xs)
            .background { PaperSheet(lift: PaperSheet.Lift(radius: 2, y: 1)) }
            .rotationEffect(moment.id.polaroidTilt)
    }
}

/// A print's size, recessed where a print would lie, with the "+" on a honey disc: the same accent as the bar's
/// button, so it reads as the place to add one in either appearance.
private struct EmptyWallSlot: View {
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .padding(Space.xs)
            .overlay { SymbolBadge(symbol: "plus") }
            .wellSurface()
    }
}

/// A moment's photo at `maxPixels`, decoded off the main thread. Until it arrives a print shows the one already decoded
/// smaller, and is blank only when there is none.
private struct MomentPhoto: View {
    let store: MomentStore
    let moment: Moment
    let maxPixels: Int
    var film = false

    @State private var loaded: UIImage?

    private var cached: UIImage? {
        film ? store.cachedFilmPrint(for: moment, maxPixels: maxPixels) : store.cachedThumbnail(for: moment, maxPixels: maxPixels)
    }

    private var standIn: UIImage? { film ? store.standInFilmPrint(for: moment, maxPixels: maxPixels) : nil }

    var body: some View {
        Color.clear
            .overlay {
                if let image = cached ?? loaded ?? standIn {
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
