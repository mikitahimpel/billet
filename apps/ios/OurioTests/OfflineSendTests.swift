import Foundation
import MomentsInterface
import ServerSync
import WidgetInterface
import WidgetUI
import Persistence
import Synchronization
import Testing
import Transport
import UsInterface
import Wire
@testable import Billet

@MainActor
@Suite(.serialized) struct UnsentTests {
    private static let accounts = AccountStore(
        load: { () throws(PersistenceError) in ("token", AccountRecord(userID: "me", deviceID: "d1", expiresAt: .max)) },
        save: { (_, _) throws(PersistenceError) in },
        setPaired: { (_, _) throws(PersistenceError) in },
        clear: { () throws(PersistenceError) in })

    @Test(arguments: [
        (Bool?.some(true), true, true),
        (Bool?.some(true), false, false),
        (Bool?.none, true, false),
        (Bool?.some(false), true, false),
        (Bool?.none, false, false),
    ])
    func theMarkShowsOnlyWhatAPairedPhoneStillHasToSend(unsent: Bool?, paired: Bool, shows: Bool) {
        #expect(UnsentMark.shows(unsent, paired: paired) == shows)
    }

    @Test func aNoteThatCouldNotGoStaysUnsentAndGoesOnTheNextTry() async throws {
        let notes = NoteStore()
        let note = try #require(notes.add(text: "later \(UUID().uuidString.prefix(6))", paper: .sky, author: "M"))
        defer { if let kept = notes.notes.first(where: { $0.id == note.id }) { notes.delete(kept) } }
        let online = Mutex(false)
        var api = APIClient.offline
        api.sendNote = { (request) async throws(TransportError) in
            guard online.withLock({ $0 }) else { throw .network("offline") }
            guard case .text(let key, let text, let paper, let stamp, let seal, let ink) = request else {
                throw .decoding
            }
            return SendNoteResponse(
                note: .text(id: NoteId(key.rawValue), author: UserId("me"), sentAt: 0, text: text, paper: paper,
                            stamp: stamp, seal: seal, ink: ink))
        }
        let sync = TextNoteSync(api: api, accounts: Self.accounts, notes: notes, partner: "L", defaults: .standard)

        #expect(await sync.sendUnsent())
        #expect(notes.unsent.contains { $0.id == note.id })

        online.withLock { $0 = true }
        #expect(await sync.sendUnsent() == false)
        #expect(!notes.unsent.contains { $0.id == note.id })
        #expect(notes.notes.first { $0.id == note.id }?.noteID == note.id.uuidString)
    }
}
