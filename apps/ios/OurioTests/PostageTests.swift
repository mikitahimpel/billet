import CoreGraphics
import Design
import Foundation
import MomentsInterface
import OurioShared
import Persistence
import ProfileInterface
import Synchronization
import Testing
import Transport
import UsInterface
import Wire
@testable import Billet

/// A note's stamp and seal: picked in the composer, kept on the note, sent to the partner and read back from them.
@MainActor
@Suite(.serialized) struct PostageTests {
    private static let accounts = AccountStore(
        load: { () throws(PersistenceError) in ("token", AccountRecord(userID: "me", deviceID: "d1", expiresAt: .max)) },
        save: { (_, _) throws(PersistenceError) in },
        setPaired: { (_, _) throws(PersistenceError) in },
        clear: { () throws(PersistenceError) in })

    @Test func everyStampAndSealHasArt() {
        #expect(Set(NoteStamp.allCases.map(\.art.rawValue)) == Set(StampArt.allCases.map(\.rawValue)))
        #expect(Set(NoteSeal.allCases.map(\.art.rawValue)) == Set(SealArt.allCases.map(\.rawValue)))
        for stamp in NoteStamp.allCases { #expect(stamp.art.rawValue == stamp.rawValue) }
        for seal in NoteSeal.allCases { #expect(seal.art.rawValue == seal.rawValue) }
    }

    @Test func theComposerKeepsTheChoiceOnTheNote() throws {
        let notes = NoteStore()
        let journal = Journal(
            moments: MomentStore(), notes: notes,
            streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"), couple: CoupleStore()) { _ in }
        let model = ComposerModel(kind: .sticky, drawing: false)
        let words = "stamped \(UUID().uuidString.prefix(6))"
        model.text = words
        model.stamp = .moon
        model.seal = .rose

        #expect(model.save(into: journal, size: CGSize(width: 280, height: 280)))
        let note = try #require(notes.notes.first { $0.text == words })
        defer { notes.delete(note) }
        #expect(note.stamp == .moon)
        #expect(note.seal == .rose)
    }

    @Test func aPlainNoteHasNeither() throws {
        let notes = NoteStore()
        let words = "plain \(UUID().uuidString.prefix(6))"
        let note = try #require(notes.add(text: words, paper: .sky, author: "M"))
        defer { notes.delete(note) }
        #expect(note.stamp == nil && note.seal == nil)
    }

    @Test func aStampAndSealGoToThePartnerWithTheText() async throws {
        let notes = NoteStore()
        let note = try #require(
            notes.add(text: "sealed \(UUID().uuidString.prefix(6))", paper: .cream, author: "M", stamp: .paw,
                      seal: .night))
        defer { if let kept = notes.notes.first(where: { $0.id == note.id }) { notes.delete(kept) } }

        let sent = Mutex<[SendNoteRequest]>([])
        var api = APIClient.offline
        api.sendNote = { (request) async throws(TransportError) in
            sent.withLock { $0.append(request) }
            guard case .text(let key, let text, let paper, let stamp, let seal, let ink) = request else {
                throw .decoding
            }
            return SendNoteResponse(
                note: .text(id: NoteId(key.rawValue), author: UserId("me"), sentAt: 0, text: text, paper: paper,
                            stamp: stamp, seal: seal, ink: ink))
        }
        let sync = TextNoteSync(api: api, accounts: Self.accounts, notes: notes, partner: "L")
        #expect(await sync.sendUnsent() == false)

        let ours = sent.withLock { $0 }.first {
            if case .text(let key, _, _, _, _, _) = $0 { key.rawValue == note.id.uuidString } else { false }
        }
        guard case .text(_, _, _, let stamp, let seal, _) = try #require(ours) else {
            Issue.record("expected a text note")
            return
        }
        #expect(stamp == .paw)
        #expect(seal == .night)
    }

    @Test func thePartnersStampAndSealArriveOnTheirNote() async throws {
        let notes = NoteStore()
        let suite = "postage-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let noteID = "n-\(UUID().uuidString)"
        let entry = NoteEntry(
            seq: 7,
            note: .text(id: NoteId(noteID), author: UserId("partner"), sentAt: 1_000,
                        text: try #require(NoteText(validating: "thinking of you")), stamp: .sun, seal: .meadow))
        var api = APIClient.offline
        api.listNotes = { (after) async throws(TransportError) in
            ListNotesResponse(notes: after == nil ? [entry] : [])
        }
        let sync = TextNoteSync(api: api, accounts: Self.accounts, notes: notes, partner: "L", defaults: defaults)
        await sync.receive()

        let received = try #require(notes.note(noteID: noteID))
        defer { notes.delete(received) }
        #expect(received.stamp == .sun)
        #expect(received.seal == .meadow)
        #expect(received.author == "L")
    }
}
