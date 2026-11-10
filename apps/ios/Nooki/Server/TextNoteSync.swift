import Foundation
import MomentsInterface
import OurioShared
import Persistence
import Transport
import UsInterface
import Wire

/// Text notes between the two phones. A note written here goes up as a text note, keyed by its local id so a retry
/// never sends it twice; the partner's text notes come down into `notes` under `partner`.
@MainActor
struct TextNoteSync {
    let api: APIClient
    let accounts: AccountStore
    let notes: NoteStore
    /// Monogram the partner's notes are kept under.
    let partner: String
    var defaults: UserDefaults = .standard

    /// Separate from the photos' and drawings' cursors.
    static let cursorKey = "texts.lastSeq"

    /// Sends every text note still waiting, oldest first. One the server refuses, such as one in an ink the pair
    /// doesn't own, goes again in the free ink; one that fails to reach it stays waiting, and so do the rest. True
    /// when that happened, so the caller tries again later.
    func sendUnsent() async -> Bool {
        for note in notes.unsent {
            guard !Task.isCancelled else { return true }
            guard let text = NoteText(validating: note.text) else { continue }
            let key = IdempotencyKey(note.id.uuidString)
            let paper = PaperColor(rawValue: note.paper.rawValue)
            let ink = note.ink.flatMap { hex in PaletteInk.bundled.first { $0.light == hex } }?.wireID ?? .free
            let sent: SendNoteResponse
            do {
                sent = try await api.sendNote(
                    .text(key: key, text: text, paper: paper, stamp: note.stamp, seal: note.seal, ink: ink))
            } catch {
                if error.isWorthRetrying { return true }
                guard ink != .free else { continue }
                do {
                    sent = try await api.sendNote(
                        .text(key: key, text: text, paper: paper, stamp: note.stamp, seal: note.seal, ink: .free))
                } catch {
                    if error.isWorthRetrying { return true }
                    continue
                }
            }
            guard case .text(let id, _, _, _, _, _, _, _) = sent.note else { continue }
            notes.setSent(note.id, noteID: id.rawValue)
        }
        return false
    }

    /// Pages through the notes after the last one looked at and keeps each text note the partner sent.
    func receive() async {
        let viewer = (try? accounts.load())?.record.userID
        var after = defaults.object(forKey: Self.cursorKey) as? Int
        while let page = try? await api.listNotes(after), let last = page.lastSeq {
            for entry in page.notes {
                guard case .text(let id, let author, let sentAt, let text, let paper, let stamp, let seal, let ink)
                        = entry.note,
                      author.rawValue != viewer else { continue }
                notes.addReceived(
                    text: text.rawValue, paper: paper.flatMap { Note.Paper(rawValue: $0.rawValue) } ?? .butter,
                    stamp: stamp, seal: seal,
                    ink: PaletteInk.bundled.first { $0.wireID == ink }?.light, author: partner,
                    date: Date(timeIntervalSince1970: Double(sentAt) / 1000), noteID: id.rawValue)
            }
            after = last
            defaults.set(last, forKey: Self.cursorKey)
        }
    }
}
