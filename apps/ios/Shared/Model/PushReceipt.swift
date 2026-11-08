import Foundation

/// When the last alert push reached this phone. The notification extension stamps it before the alert shows, so
/// Settings can tell a push that never arrived from one that did.
nonisolated struct PushReceipt: Codable, Hashable, Sendable {
    var at: Date

    static let path = "Push/received.json"

    static func last() -> Date? { SharedFile.read(PushReceipt.self, from: path)?.at }

    static func stamp(_ date: Date = .now) {
        SharedFile.write(PushReceipt(at: date), to: path)
        SharedFile.flush()
    }
}
