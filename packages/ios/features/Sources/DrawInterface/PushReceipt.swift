import Foundation
import Persistence

/// When the last alert push reached this phone. The notification extension stamps it before the alert shows, so
/// Settings can tell a push that never arrived from one that did.
public struct PushReceipt: Codable, Hashable, Sendable {
  public var at: Date

  public init(at: Date) {
    self.at = at
  }

  public static let path = "Push/received.json"

  public static func last() -> Date? { SharedFile.read(PushReceipt.self, from: path)?.at }

  public static func stamp(_ date: Date = .now) {
    SharedFile.write(PushReceipt(at: date), to: path)
    SharedFile.flush()
  }
}
