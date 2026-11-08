import PetScene
import PhotosUI
import SwiftUI
import Design
import UIKit
import Wire

// MARK: - Notes history

/// Every note and doodle the couple has left, by month, newest first; the board only has room for the latest few.
struct NotesHistory: View {
    let state: HomeState

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
        BilletSheet("All notes") {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(state.notes.notes.count) \(state.notes.notes.count == 1 ? "note" : "notes")")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)

                ForEach(months, id: \.title) { month in
                    Text(month.title)
                        .font(.nookiCallout.weight(.semibold))
                        .foregroundStyle(Ink.textSecondary)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $opened) { route in NoteSheet(state: state, id: route.id) }
    }
}

/// A note as a small square of its paper: the text or doodle, and who left it; the same grain and shadow as the prints.
private struct NoteCard: View {
    let note: Note

    @State private var doodle: UIImage?
    @Environment(ServerSession.self) private var session: ServerSession?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background { PaperSheet(color: Color(hex: note.paper.hex), lift: PaperSheet.Lift()) }
            .overlay {
                if let doodle {
                    Image(uiImage: doodle).resizable().scaledToFit().padding(12)
                } else if note.doodle == nil {
                    Text(note.text)
                        .font(.custom("Noteworthy-Bold", size: 18))
                        .foregroundStyle(Color(hex: note.inkHex))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .padding(14)
                }
            }
            .overlay(alignment: .topTrailing) {
                if note.unsent == true, session?.isPaired == true {
                    UnsentMark(size: 11, tint: Color(hex: note.inkHex).opacity(0.6)).padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("— \(note.author)")
                    .font(.custom("Noteworthy-Bold", size: 13))
                    .foregroundStyle(Color(hex: note.inkHex).opacity(0.7))
                    .padding(8)
            }
            .task(id: note.id) {
                guard let url = NoteStore.doodleURL(for: note) else { return }
                doodle = await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: 400) }.value
            }
    }
}
