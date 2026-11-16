import Foundation
import Ink
import MomentsInterface
import Persistence
import ProfileInterface
import ServerSync
import Synchronization
import Testing
import Transport
import UIKit
import Wire
@testable import Billet

@MainActor
@Suite(.serialized) struct DrawSendTests {
    private static let accounts = AccountStore(
        load: { () throws(PersistenceError) in ("token", AccountRecord(userID: "me", deviceID: "d1", expiresAt: .max)) },
        save: { (_, _) throws(PersistenceError) in },
        setPaired: { (_, _) throws(PersistenceError) in },
        clear: { () throws(PersistenceError) in })

    private static let drawing = [
        Stroke(color: "#5b3a28", width: DrawModel.penWidth, points: [Point(x: 0.2, y: 0.2), Point(x: 0.8, y: 0.7)]),
        Stroke(color: "#c0392b", width: DrawModel.penWidth, points: [Point(x: 0.3, y: 0.8), Point(x: 0.6, y: 0.4)]),
    ]

    @Test func aDrawScreenDrawingWaitsUnsentAndEveryRetryCarriesTheSameKey() async throws {
        let notes = NoteStore()
        let journal = Journal(
            moments: MomentStore(), notes: notes,
            streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"), couple: CoupleStore()) { _ in }
        let before = Set(notes.notes.map(\.id))
        #expect(DrawModel.queue(Self.drawing, canvas: CGSize(width: 390, height: 640), paper: .sky, journal: journal))
        let note = try #require(notes.notes.first { !before.contains($0.id) })
        defer { if let kept = notes.notes.first(where: { $0.id == note.id }) { notes.delete(kept) } }
        #expect(note.doodle != nil)
        #expect(note.paper == .sky)
        #expect(note.compact?.strokes.count == Self.drawing.count)
        #expect(notes.unsent.contains { $0.id == note.id })

        let online = Mutex(false)
        let keys = Mutex<[String]>([])
        var api = APIClient.offline
        api.uploadImage = { (_) async throws(TransportError) in
            UploadImageResponse(image: MediaKey("pair/\(UUID().uuidString)"))
        }
        api.sendNote = { (request) async throws(TransportError) in
            guard case .drawing(let key, let compact, let image, let paper, let stamp, let seal) = request else {
                throw .decoding
            }
            keys.withLock { $0.append(key.rawValue) }
            // The server stored the first one, but its answer never came back.
            guard online.withLock({ $0 }) else { throw .network("lost") }
            return SendNoteResponse(
                note: .drawing(
                    id: NoteId(key.rawValue), author: UserId("me"), sentAt: 0, compact: compact, image: image,
                    paper: paper, stamp: stamp, seal: seal))
        }
        let sync = TextNoteSync(api: api, accounts: Self.accounts, notes: notes, partner: "L", defaults: .standard)

        #expect(await sync.sendUnsent())
        #expect(notes.unsent.contains { $0.id == note.id })

        online.withLock { $0 = true }
        #expect(await sync.sendUnsent() == false)
        #expect(!notes.unsent.contains { $0.id == note.id })
        #expect(notes.notes.filter { !before.contains($0.id) }.count == 1)

        let ours = keys.withLock { $0 }.filter { $0 == note.id.uuidString }
        #expect(ours.count == 2)
    }

    @Test func theInboxRowOfAReceivedDrawingOpensIt() throws {
        let state = HomeState(stores: .live(events: .none))
        let png = try #require(
            UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.pngData())
        let noteID = "d-\(UUID().uuidString)"
        #expect(state.notes.addReceived(
            doodle: png, paper: .blush, stamp: nil, seal: nil, author: "L", date: .now, noteID: noteID))
        defer { if let kept = state.notes.note(noteID: noteID) { state.notes.delete(kept) } }
        let note = try #require(state.notes.note(noteID: noteID))

        state.open(.moments(NoteId(noteID)))
        #expect(state.tab == .moments)
        #expect(state.openedPin?.id == note.id)
    }
}
