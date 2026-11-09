import PetScene
import PhotosUI
import SwiftUI
import Design
import UIKit
import Wire

// MARK: - Viewer

struct MomentViewer: View {
    let state: HomeState
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var caption = ""
    @State private var confirmDelete = false
    @State private var reportFailed = false
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
                    MomentPrint(moment: moment, store: store, profile: state.profile, width: min(geo.size.width - 40, 520),
                                maxPixels: MomentStore.storedPixels, captionEditor: $caption, captionFocus: $editing)
                        .rotationEffect(.degrees(editing ? 0 : -1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 12)

                if UnsentMark.shows(moment.unsent, paired: session?.isPaired == true) {
                    UnsentLabel().padding(.bottom, 10)
                }

                if let note = moment.noteID, moment.author == state.otherPartner, let reactions = session?.reactions {
                    ReactionPicker(selected: reactions.mine(note)) { reactions.tap($0, on: NoteId(note)) }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }

                HStack(spacing: 10) {
                    // A shared photo gets reactions instead; the heart stays for ones kept only on this phone.
                    if moment.noteID == nil {
                        action(moment.loved ? "Loved" : "Love", symbol: moment.loved ? "heart.fill" : "heart",
                               tint: Color.blushPink, active: moment.loved) { store.toggleLove(moment) }
                    }
                    action(moment.pinned ? "On the wall" : "Pin to wall", symbol: moment.pinned ? "pin.fill" : "pin",
                           tint: Color.honey, active: moment.pinned) { store.togglePin(moment) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .background(Ink.screen.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: moment)
        .animation(.snappy(duration: 0.25), value: editing)
        .onAppear { caption = moment?.caption ?? "" }
        .onChange(of: caption) { _, text in
            if text.count > 40 { caption = String(text.prefix(40)) }
        }
        .onChange(of: editing) { _, now in if !now { saveCaption() } }
        .onDisappear(perform: saveCaption)
        .task(id: moment?.caption) {
            // After the cover has come up and the caption has stopped changing: the render is a main-thread
            // rasterization of a 1080 px print.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            polaroid = await renderPolaroid()
        }
        .alert("Couldn't send the report", isPresented: $reportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
        .confirmationDialog("Delete this moment?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let moment { store.delete(moment) }
                dismiss()
            }
        }
    }

    private func topBar(_ moment: Moment) -> some View {
        HStack(spacing: 12) {
            GlassIconButton(symbol: "xmark", label: "Close") { dismiss() }

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
                if let note = moment.noteID, moment.author == state.otherPartner, let session {
                    Menu {
                        ForEach(ReportReason.allCases, id: \.self) { reason in
                            Button(reason.title) {
                                report(moment, note: NoteId(note), reason: reason, session: session)
                            }
                        }
                    } label: {
                        Label("Report and hide", systemImage: "flag")
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Ink.glassGlyph)
                    .frame(width: Size.control, height: Size.control)
                    .glass(.circle, role: .control)
            }
            .accessibilityLabel("Share and more")
        }
    }

    /// Sends the report to the team, then takes the photo off this phone. Nothing is hidden if the report fails.
    private func report(_ moment: Moment, note: NoteId, reason: ReportReason, session: ServerSession) {
        Task {
            do {
                try await session.reportPartner(reason, note: note, details: nil)
                store.delete(moment)
                dismiss()
            } catch {
                reportFailed = true
            }
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
        let renderer = ImageRenderer(content: Polaroid(width: 540, caption: moment.caption, byline: state.profile.byline(of: moment),
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
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Size.button)
            .background(active ? tint.opacity(0.22) : Ink.surfaceRaised, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The five reactions to the partner's photo. Tapping the one chosen takes it back.
private struct ReactionPicker: View {
    let selected: PhotoReaction?
    let choose: (PhotoReaction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PhotoReaction.allCases, id: \.self) { reaction in
                Button { choose(reaction) } label: {
                    Text(reaction.emoji)
                        .font(.title)
                        .scaleEffect(selected == reaction ? 1.15 : 1)
                        .frame(maxWidth: .infinity)
                        .frame(height: Size.button)
                        .background(selected == reaction ? Color.honey.opacity(0.26) : Ink.surfaceRaised, in: .capsule)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selected == reaction)
                .accessibilityLabel(reaction.label)
                .accessibilityAddTraits(selected == reaction ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: selected)
    }
}
