import Observation
import UIKit
import Wire

public nonisolated struct Note: Identifiable, Codable, Hashable, Sendable {
    public enum Paper: String, Codable, CaseIterable, Sendable {
        case butter, blush, sage, sky, cream

        public var hex: UInt32 {
            switch self {
            case .butter: 0xFFE7A0
            case .blush: 0xFFC9C9
            case .sage: 0xD6E5C3
            case .sky: 0xCFE2F0
            case .cream: 0xFFFBF3
            }
        }
    }

    public let id: UUID
    /// Monogram of the partner who wrote it, "L" or "M".
    public let author: String
    public let date: Date
    /// Empty for a doodle.
    public var text: String
    /// PNG file name inside the app group's Notes folder; nil for a text note.
    public let doodle: String?
    public var paper: Paper
    public var stamp: NoteStamp? = nil
    public var seal: NoteSeal? = nil
    /// The text's ink, 0xRRGGBB; nil on notes written before inks, which keep the old brown.
    public var ink: UInt32? = nil
    /// The server's id once the note is on it; nil for notes kept on this phone only.
    public var noteID: String? = nil
    /// True while a text note written here still has to reach the partner.
    public var unsent: Bool? = nil

    public init(id: UUID, author: String, date: Date, text: String, doodle: String? = nil, paper: Paper, stamp: NoteStamp? = nil, seal: NoteSeal? = nil, ink: UInt32? = nil, noteID: String? = nil, unsent: Bool? = nil) {
        self.id = id
        self.author = author
        self.date = date
        self.text = text
        self.doodle = doodle
        self.paper = paper
        self.stamp = stamp
        self.seal = seal
        self.ink = ink
        self.noteID = noteID
        self.unsent = unsent
    }

    public var inkHex: UInt32 { ink ?? 0x5B3A28 }
}

/// The couple's notes on this phone; the JSON index and doodle PNGs live in the app group's Notes folder. Text notes
/// also go to the partner (see `TextNoteSync`); doodles stay here.
@Observable
public final class NoteStore {
    /// Longest note worth pinning on the board.
    public static let maxLength = 120

    public private(set) var notes: [Note] = []

    private static let folder = AppGroup.container.appending(path: "Notes", directoryHint: .isDirectory)
    private static let index = "Notes/notes.json"

    public init() {
        reload()
    }

    /// Picks up changes made outside this process.
    public func reload() {
        notes = SharedFile.read([Note].self, from: Self.index) ?? []
    }

    public static func doodleURL(for note: Note) -> URL? {
        note.doodle.map { folder.appending(path: $0) }
    }

    /// Empty notes are not worth saving, and long ones are cut to `maxLength`.
    @discardableResult
    public func add(
        text: String, paper: Note.Paper, author: String, ink: UInt32? = nil, stamp: NoteStamp? = nil,
        seal: NoteSeal? = nil
    ) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let note = Note(id: UUID(), author: author, date: .now, text: String(trimmed.prefix(Self.maxLength)),
                        doodle: nil, paper: paper, stamp: stamp, seal: seal, ink: ink, unsent: true)
        notes.insert(note, at: 0)
        save()
        return note
    }

    @discardableResult
    public func add(
        doodle: UIImage, paper: Note.Paper, author: String, stamp: NoteStamp? = nil, seal: NoteSeal? = nil
    ) -> Note? {
        guard let data = doodle.pngData() else { return nil }
        let file = "\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: Self.folder.appending(path: file))
        } catch {
            return nil
        }
        let note = Note(id: UUID(), author: author, date: .now, text: "", doodle: file, paper: paper, stamp: stamp,
                        seal: seal)
        notes.insert(note, at: 0)
        save()
        return note
    }

    public func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if let url = Self.doodleURL(for: note) { try? FileManager.default.removeItem(at: url) }
        save()
    }

    /// Text notes written here that the partner doesn't have yet, oldest first.
    public var unsent: [Note] { notes.filter { $0.unsent == true }.reversed() }

    public func contains(noteID: String) -> Bool { notes.contains { $0.noteID == noteID } }

    public func note(noteID: String) -> Note? { notes.first { $0.noteID == noteID } }

    public func setSent(_ id: UUID, noteID: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].unsent = nil
        notes[index].noteID = noteID
        save()
    }

    /// The partner's text note from the server, in date order with the rest.
    public func addReceived(
        text: String, paper: Note.Paper, stamp: NoteStamp? = nil, seal: NoteSeal? = nil, ink: UInt32?,
        author: String, date: Date, noteID: String
    ) {
        guard !contains(noteID: noteID) else { return }
        let note = Note(id: UUID(), author: author, date: date, text: text, doodle: nil, paper: paper, stamp: stamp,
                        seal: seal, ink: ink, noteID: noteID)
        notes.insert(note, at: notes.firstIndex { $0.date < date } ?? notes.endIndex)
        save()
    }

    public func latest(notBy viewer: String) -> Note? {
        notes.first { $0.author != viewer }
    }

    private func save() {
        SharedFile.write(notes, to: Self.index)
    }
}
