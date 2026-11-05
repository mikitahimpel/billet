import ActivityKit
import Foundation
import Ink
import Wire

/// The partner's drawing as a Live Activity: on the lock screen and in the Dynamic Island. Only the server starts one,
/// with a push-to-start push (packages/backend/platform/src/apns-payloads.ts). That push names this type in
/// `attributes-type`, so the name must not change. `ContentState` decodes the push's `content-state`, which is the
/// `LiveActivity` push payload; its `_tag` is ignored.
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
