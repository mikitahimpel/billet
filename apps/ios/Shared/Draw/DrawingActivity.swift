import ActivityKit
import Foundation
import Ink
import Wire

/// The partner's drawing as a Live Activity, started only by the server's push-to-start
/// (packages/backend/platform/src/apns-payloads.ts), which names this type in `attributes-type`: never rename it.
/// `ContentState` decodes the push's `content-state` (the `LiveActivity` push payload); its `_tag` is ignored.
nonisolated struct DrawingAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        let noteId: String
        let author: String
        let compact: CompactStrokes
        let paper: PaperColor?

        /// The full strokes, or none if the compact rendition does not decode.
        var strokes: [Stroke] { (try? InkDecoder.decode(compact)) ?? [] }
    }

    let noteId: String
}
