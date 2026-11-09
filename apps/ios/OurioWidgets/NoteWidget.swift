import OurioShared
import SwiftUI
import Design
import WidgetKit

/// Lock Screen: the note your partner left last, or a pencil if the board is empty. Tap to write one back.
struct NoteAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.note", provider: NoteProvider()) { entry in
            NoteAccessoryView(entry: entry)
        }
        .configurationDisplayName("Note")
        .description("Your partner's latest note. Tap to write one back.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct NoteEntry: TimelineEntry {
    let date: Date
    let note: Note?
    let doodle: UIImage?
}

struct NoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        Self.sample()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NoteEntry) -> Void) {
        completion(context.isPreview ? Self.sample() : entry())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NoteEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    /// The app reloads the timeline on every save, so one entry is enough.
    private func entry() -> NoteEntry {
        let note = NoteStore().latest(notBy: CoupleStore().couple.viewer)
        let doodle = note.flatMap(NoteStore.doodleURL(for:)).flatMap { Downsample.image(at: $0, maxPixels: 300) }
        return NoteEntry(date: .now, note: note, doodle: doodle)
    }

    private static func sample() -> NoteEntry {
        NoteEntry(date: .now,
                  note: Note(id: UUID(), author: "M", date: .now, text: "miss you already", doodle: nil, paper: .butter),
                  doodle: nil)
    }
}

private struct NoteAccessoryView: View {
    let entry: NoteEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(DeepLink.newNote.url)
        default:
            rectangular
                .containerBackground(for: .widget) {}
                .widgetURL(DeepLink.newNote.url)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            if let note = entry.note {
                if let doodle = entry.doodle {
                    Image(uiImage: doodle)
                        .resizable()
                        .scaledToFit()
                }
                noteBody(note)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func noteBody(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.doodle == nil {
                Text(note.text)
                    .font(.ourioCaption.weight(.semibold))
                    .lineLimit(3)
                    .widgetAccentable()
            }
            Text("— \(note.author)")
                .font(.ourioCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Leave a note", systemImage: "pencil.and.scribble")
                .font(.ourioCallout.weight(.bold))
            Text("for \(CatProfile.name())'s board")
                .font(.ourioCaption)
                .foregroundStyle(.secondary)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Control Center and Lock Screen button: opens Ourio straight into a blank note.
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ourio.app.new-note") {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Note")
        .description("Write a note for your cat's board.")
    }
}
