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

    private let hMargin: CGFloat = 16
    /// Same tab bar clearance as the shop.
    private let bottomInset: CGFloat = 134
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

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
                        grid
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
        .sheet(item: $draft) { draft in
            ComposeSheet(image: draft.image) { caption in
                withAnimation(.spring(duration: 0.4)) { _ = state.addMoment(draft.image, caption: caption) }
            }
        }
        .sheet(isPresented: $showsHistory) {
            NotesHistory(state: state)
        }
        .sheet(item: $state.openedPin) { route in
            if store.moments.contains(where: { $0.id == route.id }) {
                MomentSheet(state: state, id: route.id)
            } else if notes.contains(where: { $0.id == route.id }) {
                NoteSheet(state: state, id: route.id)
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
            if notes.isEmpty {
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
            let count = min(notes.count, BoardRoomScene.slots)
            return notes.isEmpty ? nil : "\(count) \(count == 1 ? "note" : "notes") on the board"
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

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(store.moments.enumerated()), id: \.element.id) { index, moment in
                Button { state.openedPin = PinRoute(id: moment.id) } label: {
                    PolaroidCard(moment: moment, store: store)
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.6 : 1.4))
                }
                .buttonStyle(.plain)
            }
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
                        ForEach(Array(month.notes.enumerated()), id: \.element.id) { index, note in
                            Button { opened = PinRoute(id: note.id) } label: {
                                NoteCard(note: note)
                                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.6 : 1.4))
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

/// A note as a small square of its paper: the text or doodle, and who left it.
private struct NoteCard: View {
    let note: Note

    @State private var doodle: UIImage?

    var body: some View {
        Color(hex: note.paper.hex)
            .aspectRatio(1, contentMode: .fit)
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
            .clipShape(.rect(cornerRadius: 4))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
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
        .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Cards

/// Polaroid card: white frame, square photo, a handwritten-looking caption in the wide bottom margin.
struct PolaroidCard: View {
    let moment: Moment
    let store: MomentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(hex: 0xE9D6BC)
                .aspectRatio(1, contentMode: .fit)
                .overlay { MomentPhoto(store: store, moment: moment, maxPixels: 512) }
                .clipShape(.rect(cornerRadius: 3))
                .overlay(alignment: .topTrailing) {
                    if moment.loved {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.blushPink, in: .circle)
                            .padding(6)
                    }
                }

            Text(moment.caption.isEmpty ? moment.date.formatted(.dateTime.day().month()) : moment.caption)
                .font(.custom("Noteworthy-Bold", size: 14))
                .foregroundStyle(Color(hex: 0x5B3A28))
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .padding(8)
        .padding(.bottom, 4)
        .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 5))
        .overlay(alignment: .top) {
            if moment.pinned {
                // A little washi tape strip marks the ones hanging in the room.
                Rectangle()
                    .fill(Color.blushPink.opacity(0.75))
                    .frame(width: 46, height: 16)
                    .rotationEffect(.degrees(-4))
                    .offset(y: -8)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
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

    @State private var loaded: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = store.cachedThumbnail(for: moment, maxPixels: maxPixels) ?? loaded {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .task(id: moment.file) {
                // A wall slot can switch moments; don't keep showing the previous photo meanwhile.
                loaded = nil
                loaded = await store.thumbnail(for: moment, maxPixels: maxPixels)
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
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("New moment")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: 3))
                TextField("", text: $caption, prompt: Text("Write a little note…").foregroundStyle(Color(hex: 0xB8957A)))
                    .font(.custom("Noteworthy-Bold", size: 17))
                    .foregroundStyle(Color(hex: 0x5B3A28))
                    .focused($focused)
                    .submitLabel(.done)
                    .frame(width: 220)
                    .onChange(of: caption) { _, text in
                        if text.count > 40 { caption = String(text.prefix(40)) }
                    }
            }
            .padding(10)
            .padding(.bottom, 8)
            .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 5))
            .rotationEffect(.degrees(-1.5))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

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
        .usSheet()
    }
}

// MARK: - Viewer

private struct MomentSheet: View {
    let state: HomeState
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var store: MomentStore { state.moments }
    private var moment: Moment? { store.moments.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 22) {
            if let moment {
                VStack(alignment: .leading, spacing: 12) {
                    Color(hex: 0xE9D6BC)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { MomentPhoto(store: store, moment: moment, maxPixels: MomentStore.storedPixels) }
                        .clipShape(.rect(cornerRadius: 3))
                    if !moment.caption.isEmpty {
                        Text(moment.caption)
                            .font(.custom("Noteworthy-Bold", size: 19))
                            .foregroundStyle(Color(hex: 0x5B3A28))
                    }
                    HStack(spacing: 6) {
                        Monogram(partner: moment.author, profile: state.profile, size: 20)
                        Text(moment.date.formatted(date: .long, time: .omitted))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0x9A7A62))
                    }
                }
                .padding(12)
                .padding(.bottom, 6)
                .background(Color(hex: 0xFFFBF3), in: .rect(cornerRadius: 6))
                .rotationEffect(.degrees(-1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.horizontal, 28)
                .padding(.top, 30)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    action(moment.loved ? "Loved" : "Love", symbol: moment.loved ? "heart.fill" : "heart",
                           tint: Color.blushPink, active: moment.loved) { store.toggleLove(moment) }
                    action(moment.pinned ? "On the wall" : "Pin to wall", symbol: moment.pinned ? "pin.fill" : "pin",
                           tint: Color.honey, active: moment.pinned) { store.togglePin(moment) }
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.1), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .confirmationDialog("Delete this moment?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        store.delete(moment)
                        dismiss()
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: moment)
        .usSheet()
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
