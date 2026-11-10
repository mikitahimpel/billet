import Foundation
import Persistence
import Wire

/// The newest drawing the partner sent, as the widgets show it. The app writes it when it fetches notes or one
/// arrives over the socket; the notification extension writes it from a push. The compact strokes need no network.
public nonisolated struct LatestDrawing: Codable, Hashable, Sendable {
    public let noteID: String
    public let seq: Int?
    public let sentAt: Date
    public let compact: CompactStrokes
    public let paper: PaperColor?

    public static let path = "Drawings/latest.json"
    /// WidgetKit kind of the drawing widgets, so a write reloads only them.
    public static let widgetKind = "com.ourio.app.drawing"

    public static func load() -> LatestDrawing? { SharedFile.read(LatestDrawing.self, from: path) }

    /// Saves this drawing unless the one already saved is the same note or newer. Returns whether it saved.
    @discardableResult
    public func saveIfNewer() -> Bool {
        if let saved = Self.load(), saved.noteID == noteID || saved.sentAt > sentAt { return false }
        SharedFile.write(self, to: Self.path)
        SharedFile.flush()
        return true
    }

    /// The partner's drawing in `note`, or nil for any other note or one of this phone's own.
    public init?(_ note: Wire.Note, seq: Int?, viewer: String?) {
        guard case .drawing(let id, let author, let sentAt, let compact, _, let paper, _, _) = note,
              author.rawValue != viewer else { return nil }
        self.init(noteID: id.rawValue, seq: seq, sentAt: Date(timeIntervalSince1970: Double(sentAt) / 1000),
                  compact: compact, paper: paper)
    }

    /// The drawing in a push's custom data, or nil for any other note. A push says nothing of when the note was sent,
    /// so it counts as sent `now`.
    public init?(push userInfo: [AnyHashable: Any], now: Date = .now) {
        guard let payload = PushPayload(push: userInfo) else { return nil }
        switch payload {
        case .alert(let noteId, _, let compact?, _, let paper), .widget(let noteId, _, let compact?, _, let paper),
             .liveActivity(let noteId, _, let compact, let paper):
            self.init(noteID: noteId.rawValue, seq: nil, sentAt: now, compact: compact, paper: paper)
        case .alert, .widget, .reaction:
            return nil
        }
    }

    public init(noteID: String, seq: Int?, sentAt: Date, compact: CompactStrokes, paper: PaperColor?) {
        self.noteID = noteID
        self.seq = seq
        self.sentAt = sentAt
        self.compact = compact
        self.paper = paper
    }
}
