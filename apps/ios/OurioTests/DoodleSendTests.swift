import Foundation
import Ink
import MomentsInterface
import Persistence
import PencilKit
import ServerSync
import Synchronization
import Testing
import Transport
import UIKit
import Wire
@testable import Billet

@MainActor
@Suite(.serialized) struct DoodleSendTests {
    private static let accounts = AccountStore(
        load: { () throws(PersistenceError) in ("token", AccountRecord(userID: "me", deviceID: "d1", expiresAt: .max)) },
        save: { (_, _) throws(PersistenceError) in },
        setPaired: { (_, _) throws(PersistenceError) in },
        clear: { () throws(PersistenceError) in })

    private static let canvas = CGSize(width: 390, height: 520)

    /// A finger scribbling for a while: 40 strokes of 300 samples each, far more than a push can carry.
    private static func fingerDoodle() -> PKDrawing {
        let strokes = (0..<40).map { index in
            let points = (0..<300).map { step in
                let t = Double(step) / 299
                let x = 20 + 350 * t
                let y = 40 + Double(index) * 11 + 30 * sin(t * 14 * .pi + Double(index)) + 2 * sin(Double(step) * 1.7)
                return PKStrokePoint(
                    location: CGPoint(x: x, y: y), timeOffset: t, size: CGSize(width: 6, height: 6), opacity: 1,
                    force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(
                ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
        }
        return PKDrawing(strokes: strokes)
    }

    private static let picture = UIGraphicsImageRenderer(size: CGSize(width: 560, height: 560)).image { context in
        UIColor.black.setStroke()
        context.cgContext.stroke(CGRect(x: 40, y: 40, width: 480, height: 480))
    }

    @Test func aBigFingerDoodleTravelsWithinThePushBudget() throws {
        let compact = ComposerModel.compact(Self.fingerDoodle(), canvas: Self.canvas)
        #expect(!compact.strokes.isEmpty)
        #expect(try InkEncoder.byteCount(compact) <= InkEncoder.Parameters().budget)
        #expect(compact.strokes.allSatisfy { InkColor.isValid($0.color) })
    }

    @Test func aDoodleGoesToThePartnerAsADrawingAndWaitsWhileOffline() async throws {
        let notes = NoteStore()
        let compact = ComposerModel.compact(Self.fingerDoodle(), canvas: Self.canvas)
        let note = try #require(
            notes.add(doodle: Self.picture, compact: compact, paper: .blush, author: "M", stamp: .paw))
        defer { if let kept = notes.notes.first(where: { $0.id == note.id }) { notes.delete(kept) } }
        #expect(notes.unsent.contains { $0.id == note.id })

        let online = Mutex(false)
        let uploaded = Mutex<[Data]>([])
        let sent = Mutex<[SendNoteRequest]>([])
        var api = APIClient.offline
        api.uploadImage = { (png) async throws(TransportError) in
            guard online.withLock({ $0 }) else { throw .network("offline") }
            uploaded.withLock { $0.append(png) }
            return UploadImageResponse(image: MediaKey("pair/\(UUID().uuidString)"))
        }
        api.sendNote = { (request) async throws(TransportError) in
            sent.withLock { $0.append(request) }
            guard case .drawing(let key, let compact, let image, let paper, let stamp, let seal) = request else {
                throw .decoding
            }
            if stamp != nil { throw .api(.postageNotOwned(postage: PostageId(NoteStamp.paw))) }
            return SendNoteResponse(
                note: .drawing(id: NoteId(key.rawValue), author: UserId("me"), sentAt: 0, compact: compact,
                               image: image, paper: paper, stamp: stamp, seal: seal))
        }
        let sync = TextNoteSync(api: api, accounts: Self.accounts, notes: notes, partner: "L", defaults: .standard)

        #expect(await sync.sendUnsent())
        #expect(notes.unsent.contains { $0.id == note.id })
        #expect(sent.withLock { $0 }.isEmpty)

        online.withLock { $0 = true }
        #expect(await sync.sendUnsent() == false)
        #expect(!notes.unsent.contains { $0.id == note.id })
        #expect(notes.notes.first { $0.id == note.id }?.noteID == note.id.uuidString)

        let png = try #require(uploaded.withLock { $0 }.first)
        #expect(UIImage(data: png) != nil)
        let ours = sent.withLock { $0 }.filter {
            if case .drawing(let key, _, _, _, _, _) = $0 { key.rawValue == note.id.uuidString } else { false }
        }
        #expect(ours.count == 2)
        guard case .drawing(_, let carried, _, let paper, let stamp, _) = try #require(ours.last) else {
            Issue.record("expected a drawing")
            return
        }
        #expect(carried == compact)
        #expect(paper == .blush)
        #expect(stamp == nil)
    }

    @Test func queuingAgainLeavesSentAndReceivedDoodlesAlone() throws {
        let notes = NoteStore()
        let png = try #require(Self.picture.pngData())
        let mine = try #require(
            notes.add(doodle: Self.picture, compact: CompactStrokes(strokes: []), paper: .sky, author: "M"))
        notes.setSent(mine.id, noteID: "sent-\(mine.id)")
        let theirs = "got-\(UUID().uuidString)"
        #expect(notes.addReceived(doodle: png, paper: .sky, stamp: nil, seal: nil, author: "M", date: .now,
                                  noteID: theirs))
        defer {
            for id in ["sent-\(mine.id)", theirs] { if let kept = notes.note(noteID: id) { notes.delete(kept) } }
        }

        notes.queueDoodles(by: "M", since: .distantPast)
        #expect(!notes.unsent.contains { $0.noteID == "sent-\(mine.id)" || $0.noteID == theirs })
    }

    @Test func thePartnersDrawingLandsOnTheBoardOnceItsPictureDownloads() async throws {
        let notes = NoteStore()
        let suite = "doodles-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let noteID = "n-\(UUID().uuidString)"
        let text = "t-\(UUID().uuidString)"
        let entries = [
            NoteEntry(seq: 3, note: .drawing(id: NoteId(noteID), author: UserId("partner"), sentAt: 2_000,
                                             compact: CompactStrokes(strokes: []), image: MediaKey("pair/doodle"),
                                             paper: .sage, seal: .night)),
            NoteEntry(seq: 4, note: .text(id: NoteId(text), author: UserId("partner"), sentAt: 3_000,
                                          text: try #require(NoteText(validating: "and this")))),
        ]
        let online = Mutex(false)
        var api = APIClient.offline
        api.listNotes = { (after) async throws(TransportError) in
            ListNotesResponse(notes: entries.filter { $0.seq > (after ?? 0) })
        }
        let png = try #require(Self.picture.pngData())
        api.downloadImage = { (_) async throws(TransportError) in
            guard online.withLock({ $0 }) else { throw .network("offline") }
            return png
        }
        let sync = TextNoteSync(api: api, accounts: Self.accounts, notes: notes, partner: "L", defaults: defaults)
        defer {
            for id in [noteID, text] { if let kept = notes.note(noteID: id) { notes.delete(kept) } }
        }

        await sync.receive()
        #expect(notes.note(noteID: noteID) == nil)
        #expect(notes.note(noteID: text) == nil)

        online.withLock { $0 = true }
        await sync.receive()
        let drawing = try #require(notes.note(noteID: noteID))
        #expect(drawing.author == "L")
        #expect(drawing.paper == .sage)
        #expect(drawing.seal == .night)
        #expect(drawing.unsent == nil)
        let url = try #require(NoteStore.doodleURL(for: drawing))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(notes.note(noteID: text) != nil)
    }

    @Test func framesArrivingTogetherDownloadThePartnersDrawingOnce() async throws {
        let notes = NoteStore()
        let suite = "doodles-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let noteID = "n-\(UUID().uuidString)"
        let entry = NoteEntry(seq: 7, note: .drawing(id: NoteId(noteID), author: UserId("partner"), sentAt: 2_000,
                                                     compact: CompactStrokes(strokes: []),
                                                     image: MediaKey("pair/doodle"), paper: .sky))
        let downloads = Mutex(0)
        var api = APIClient.offline
        api.listNotes = { (after) async throws(TransportError) in
            ListNotesResponse(notes: [entry].filter { $0.seq > (after ?? 0) })
        }
        let png = try #require(Self.picture.pngData())
        api.downloadImage = { (_) async throws(TransportError) in
            downloads.withLock { $0 += 1 }
            try? await Task.sleep(for: .milliseconds(50))
            return png
        }
        let receiving = PhotoReceiving()
        let sync = TextNoteSync(
            api: api, accounts: Self.accounts, notes: notes, partner: "L", defaults: defaults, receiving: receiving)
        defer { if let kept = notes.note(noteID: noteID) { notes.delete(kept) } }

        async let first: Void = sync.receive()
        async let second: Void = sync.receive()
        _ = await (first, second)

        #expect(downloads.withLock { $0 } == 1)
        #expect(notes.notes.filter { $0.noteID == noteID }.count == 1)
        #expect(defaults.integer(forKey: TextNoteSync.cursorKey) == 7)
    }
}
