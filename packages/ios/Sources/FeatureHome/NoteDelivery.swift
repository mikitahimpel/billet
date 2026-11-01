import Foundation
import Pet
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
    /// The partner petted the cat.
    case partnerPetted
    /// The room's table of treats: day to the devices that gave one.
    case treats([String: Set<String>])
  }

  /// This device's ID, to tell its own treats from the partner's.
  public var device: String
  public var deliver: @Sendable ([Stroke]) async -> Void
  /// Tells the partner's phone about a pet or a treat. `at` is an ISO time in the sender's calendar.
  public var play: @Sendable (PlayKind, _ at: String) async -> Void
  /// Holds the connection open for as long as the stream is being read.
  public var updates: @Sendable () -> AsyncStream<Update>
  public var pushTokenChanged: @Sendable () async -> Void

  public init(
    device: String = "",
    deliver: @escaping @Sendable ([Stroke]) async -> Void,
    play: @escaping @Sendable (PlayKind, String) async -> Void = { _, _ in },
    updates: @escaping @Sendable () -> AsyncStream<Update> = { AsyncStream { $0.finish() } },
    pushTokenChanged: @escaping @Sendable () async -> Void = {}
  ) {
    self.device = device
    self.play = play
    self.deliver = deliver
    self.updates = updates
    self.pushTokenChanged = pushTokenChanged
  }

  /// Delivery through the room socket at `url`, while the app is open.
  public static func live(url: URL, device: String) -> NoteDelivery {
    let socket = LiveDelivery(url: url)
    return NoteDelivery(
      device: device,
      deliver: { await socket.send($0) },
      play: { await socket.play($0, at: $1) },
      updates: {
        AsyncStream { continuation in
          let connection = Task {
            await socket.run(continuation)
            continuation.finish()
          }
          continuation.onTermination = { _ in connection.cancel() }
        }
      },
      pushTokenChanged: { await socket.sendPushToken() })
  }

  /// FAKE. Nothing leaves the device and nothing arrives. For tests.
  public static let localFake = NoteDelivery { _ in }
}
