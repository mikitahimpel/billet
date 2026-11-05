import Foundation
import Testing
import Wire
@testable import Billet

struct DrawingWidgetTests {
    static let compact = CompactStrokes(strokes: [CompactStroke(color: "#7B4FE0", width: 33, points: [10, 20, 500, 900])])

    private func push(_ payload: PushPayload) throws -> [AnyHashable: Any] {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
        return [LatestDrawing.pushKey: json, "aps": ["alert": ["title": "Anya"]]]
    }

    @Test func aDrawingPushBecomesTheLatestDrawing() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let info = try push(.alert(noteId: NoteId("n1"), author: UserId("anya"), compact: Self.compact, paper: .sky))
        let drawing = try #require(LatestDrawing(push: info, now: now))
        #expect(drawing.noteID == "n1")
        #expect(drawing.paper == .sky)
        #expect(drawing.sentAt == now)
        #expect(drawing.strokes.first?.points.count == 2)
    }

    @Test func otherPushesAreNotDrawings() throws {
        let text = try push(.alert(noteId: NoteId("n2"), author: UserId("anya"), compact: nil, text: NoteText(validating: "hi")))
        #expect(LatestDrawing(push: text) == nil)
        #expect(LatestDrawing(push: ["aps": ["alert": "x"]]) == nil)
        #expect(LatestDrawing(push: [LatestDrawing.pushKey: "not json"]) == nil)
    }

    @Test func onlyThePartnersDrawingNotesCount() {
        let mine = Wire.Note.drawing(id: NoteId("a"), author: UserId("me"), sentAt: 5_000, compact: Self.compact,
                                image: MediaKey("k"))
        let theirs = Wire.Note.drawing(id: NoteId("b"), author: UserId("anya"), sentAt: 6_000, compact: Self.compact,
                                  image: MediaKey("k"), paper: .butter)
        #expect(LatestDrawing(mine, seq: 1, viewer: "me") == nil)
        let drawing = LatestDrawing(theirs, seq: 2, viewer: "me")
        #expect(drawing?.sentAt == Date(timeIntervalSince1970: 6))
        #expect(drawing?.paper == .butter)
    }

    @Test func aPaperPicksItsWallpaper() {
        #expect(LockWallpaper(paper: nil) == .blush)
        for wallpaper in LockWallpaper.allCases { #expect(LockWallpaper(paper: wallpaper.paper) == wallpaper) }
    }

    @Test func aDrawingIsFittedInsideTheWidget() {
        let strokes = [Stroke(color: "#7B4FE0", width: 0.03, points: [Point(x: 0.1, y: 1.2), Point(x: 0.9, y: 1.9)])]
        let size = CGSize(width: 340, height: 160)
        let fitted = DrawingCard.fitted(strokes, in: size, margin: 0.1)
        let aspect = size.height / size.width
        for point in fitted.flatMap(\.points) {
            #expect((0...1).contains(point.x))
            #expect((0...aspect).contains(point.y))
        }
    }
}
