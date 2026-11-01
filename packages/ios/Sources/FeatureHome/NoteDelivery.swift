import Foundation
import Wire

/// Sends finished drawings to the partner and reports what arrives from them.
public struct NoteDelivery: Sendable {
  public enum Status: Hashable, Sendable {
    case connecting
    case partnerAway
    case partnerHere
    /// The room turned this device away, so reconnecting cannot help.
    case refused
  }

  public enum Update: Hashable, Sendable {
    case status(Status)
    case note([Stroke])
  }

  public var deliver: @Sendable ([Stroke]) async -> Void
  /// Holds the connection open for as long as the stream is being read.
  public var updates: @Sendable () -> AsyncStream<Update>

  public init(
    deliver: @escaping @Sendable ([Stroke]) async -> Void,
    updates: @escaping @Sendable () -> AsyncStream<Update> = { AsyncStream { $0.finish() } }
  ) {
    self.deliver = deliver
    self.updates = updates
  }

  /// Delivery through the room socket at `url`, while the app is open.
  public static func live(url: URL) -> NoteDelivery {
    let socket = LiveDelivery(url: url)
    return NoteDelivery(
      deliver: { await socket.send($0) },
      updates: {
        AsyncStream { continuation in
          let connection = Task {
            await socket.run(continuation)
            continuation.finish()
          }
          continuation.onTermination = { _ in connection.cancel() }
        }
      })
  }

  /// FAKE. Nothing leaves the device and nothing arrives. For tests.
  public static let localFake = NoteDelivery { _ in }
}
