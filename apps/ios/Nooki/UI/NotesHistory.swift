import MomentsInterface
import WidgetInterface
import WidgetUI
import PetScene
import PhotosUI
import SwiftUI
import Design
import UIKit
import UsInterface
import Wire

// MARK: - Notes history

/// Every note the couple has left; the board only has room for the latest few.
struct NotesHistory: View {
    let state: HomeState

    @State private var opened: PinRoute?

    private let columns = [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible(), spacing: Space.l)]

    private var months: [(title: String, notes: [Note])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: state.notes.notes) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted(by: >).map { start in
            (start.formatted(.dateTime.month(.wide).year()), groups[start] ?? [])
        }
    }

    var body: some View {
        let count = state.notes.notes.count
        BilletSheet("All notes", subtitle: "\(count) \(count == 1 ? "note" : "notes")") {
            VStack(alignment: .leading, spacing: Space.l) {
                ForEach(months, id: \.title) { month in
                    SectionHeader(month.title)
                        .padding(.top, Space.xs)
                    LazyVGrid(columns: columns, spacing: Space.l + Space.xs) {
                        ForEach(month.notes) { note in
                            Button { opened = PinRoute(id: note.id) } label: {
                                NoteCard(note: note)
                                    .rotationEffect(note.id.polaroidTilt)
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $opened) { route in NoteSheet(state: state, id: route.id) }
    }
}

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
                    Image(uiImage: doodle).resizable().scaledToFit().padding(Space.m)
                } else if note.doodle == nil {
                    Text(note.text)
                        .font(.custom("Noteworthy-Bold", size: 18))
                        .foregroundStyle(Color(hex: note.inkHex))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .padding(Space.l)
                }
            }
            .overlay {
                GeometryReader { proxy in
                    Color.clear.postage(of: note, width: proxy.size.width)
                }
            }
            .overlay(alignment: .topTrailing) {
                if UnsentMark.shows(note.unsent, paired: session?.isPaired == true) {
                    UnsentMark(size: 11, tint: Color(hex: note.inkHex).opacity(0.6)).padding(Space.s)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("— \(note.author)")
                    .font(.custom("Noteworthy-Bold", size: 13))
                    .foregroundStyle(Color(hex: note.inkHex).opacity(0.7))
                    .padding(Space.s)
            }
            .task(id: note.id) {
                guard let url = NoteStore.doodleURL(for: note) else { return }
                doodle = await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: 400) }.value
            }
    }
}
