import Observation
import UIKit

/// A little note for the couple: a line of text or a doodle on a colored piece of paper.
nonisolated struct Note: Identifiable, Codable, Hashable {
    /// The paper colors a note can be pinned on.
    enum Paper: String, Codable, CaseIterable {
        case butter, blush, sage, sky, cream

        var hex: UInt32 {
            switch self {
            case .butter: 0xFFE7A0
            case .blush: 0xFFC9C9
            case .sage: 0xD6E5C3
            case .sky: 0xCFE2F0
            case .cream: 0xFFFBF3
            }
        }
    }

    let id: UUID
    /// Monogram of the partner who wrote it, "L" or "M".
    let author: String
    let date: Date
    /// Empty for a doodle.
    var text: String
    /// PNG file name inside the app group's Notes folder; nil for a text note.
    let doodle: String?
    var paper: Paper
    /// The text's ink, 0xRRGGBB; nil on notes written before inks, which keep the old brown.
    var ink: UInt32? = nil

    var inkHex: UInt32 { ink ?? 0x5B3A28 }
}

/// Local-only notes store; the JSON index and doodle PNGs live in the app group's Notes folder.
@Observable
final class NoteStore {
    /// Longest note worth pinning on the board.
    static let maxLength = 120

    private(set) var notes: [Note] = []

    private static let folder = AppGroup.container.appending(path: "Notes", directoryHint: .isDirectory)
    private static let index = "Notes/notes.json"

    init() {
        reload()
    }

    /// Picks up changes made outside this process.
    func reload() {
        notes = SharedFile.read([Note].self, from: Self.index) ?? []
    }

    static func doodleURL(for note: Note) -> URL? {
        note.doodle.map { folder.appending(path: $0) }
    }

    /// Empty notes are not worth saving, and long ones are cut to `maxLength`.
    @discardableResult
    func add(text: String, paper: Note.Paper, author: String, ink: UInt32? = nil) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let note = Note(id: UUID(), author: author, date: .now, text: String(trimmed.prefix(Self.maxLength)),
                        doodle: nil, paper: paper, ink: ink)
        notes.insert(note, at: 0)
        save()
        return note
    }

    @discardableResult
    func add(doodle: UIImage, paper: Note.Paper, author: String) -> Note? {
        guard let data = doodle.pngData() else { return nil }
        let file = "\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: Self.folder.appending(path: file))
        } catch {
            return nil
        }
        let note = Note(id: UUID(), author: author, date: .now, text: "", doodle: file, paper: paper)
        notes.insert(note, at: 0)
        save()
        return note
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if let url = Self.doodleURL(for: note) { try? FileManager.default.removeItem(at: url) }
        save()
    }

    /// Newest note not written by `viewer`.
    func latest(notBy viewer: String) -> Note? {
        notes.first { $0.author != viewer }
    }

    private func save() {
        SharedFile.write(notes, to: Self.index)
    }
}
