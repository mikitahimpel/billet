import SwiftUI
import Design
import UIKit

/// One note opened from the board: the paper big, its text or doodle, and a way to take it down.
struct NoteSheet: View {
    let state: HomeState
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var doodle: UIImage?

    private var note: Note? { state.notes.notes.first { $0.id == id } }

    var body: some View {
        BilletSheet("Note", size: .fit) {
            if let note {
                VStack(spacing: Space.l + 6) {
                    face(note)
                        .rotationEffect(.degrees(-1))
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .padding(.top, Space.s)

                    HStack(spacing: 6) {
                        Monogram(partner: note.author, profile: state.profile, size: 20)
                        Text(note.date.formatted(date: .long, time: .omitted))
                            .font(.nookiCaption)
                            .foregroundStyle(Ink.textSecondary)
                    }

                    SecondaryButton("Delete note", symbol: "trash") { confirmDelete = true }
                        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                state.notes.delete(note)
                                dismiss()
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.snappy(duration: 0.25), value: note)
        .task(id: id) { await loadDoodle() }
    }

    private func face(_ note: Note) -> some View {
        ZStack {
            Color(hex: note.paper.hex)
            if let doodle {
                Image(uiImage: doodle).resizable().scaledToFit().padding(24)
            } else {
                Text(note.text)
                    .font(.custom("Noteworthy-Bold", size: 30))
                    .foregroundStyle(Color(hex: note.inkHex))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .padding(26)
            }
        }
        .frame(width: 300, height: 300)
    }

    private func loadDoodle() async {
        guard let note, let url = NoteStore.doodleURL(for: note) else { return }
        doodle = await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: 480) }.value
    }
}
