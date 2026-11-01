import DesignSystem
import Foundation
import Labs
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
    case note([Stroke], id: UUID)
    /// The partner petted the cat.
    case partnerPetted
    /// The room's table of treats: day to the devices that gave one.
    case treats([String: Set<String>])
    /// The name the room holds for the cat.
    case catName(String)
    /// The room's table of reactions: note to the reaction its receiver sent.
    case reactions([UUID: Reaction])
    /// The partner opened a note this device sent. Only the fake partner says this for now: the
    /// room has no frame for it.
    case noteOpened(UUID)
    /// A note from the partner that stays closed until `opensAt`. Only the fake partner sends
    /// these for now: the room has no frame for them.
    case sealedNote([Stroke], id: UUID, opensAt: Date)
    /// The partner put a finger on the cat, or lifted it. Only the fake partner says this for
    /// now: the room has no realtime frame for it.
    case partnerHolding(Bool)
    /// The colour of the partner's lamp. Only the fake partner says this for now: the room has no
    /// frame for it.
    case partnerGlow(PartnerGlow)
  }

  /// This device's ID, to tell its own treats from the partner's.
  public var device: String
  /// Sends a drawing under `id`, which is also the ID of the note the partner receives.
  public var deliver: @Sendable ([Stroke], UUID) async -> Void
  /// Tells the partner's phone about a pet or a treat. `at` is an ISO time in the sender's calendar.
  public var play: @Sendable (PlayKind, _ at: String) async -> Void
  /// Names the cat. The room keeps the first name from either partner.
  public var nameCat: @Sendable (String) async -> Void
  /// Sends a reaction to a note the partner sent.
  public var react: @Sendable (_ note: UUID, Reaction) async -> Void
  /// Holds the connection open for as long as the stream is being read.
  public var updates: @Sendable () -> AsyncStream<Update>
  public var pushTokenChanged: @Sendable () async -> Void

  public init(
    device: String = "",
    deliver: @escaping @Sendable ([Stroke], UUID) async -> Void,
    play: @escaping @Sendable (PlayKind, String) async -> Void = { _, _ in },
    nameCat: @escaping @Sendable (String) async -> Void = { _ in },
    react: @escaping @Sendable (UUID, Reaction) async -> Void = { _, _ in },
    updates: @escaping @Sendable () -> AsyncStream<Update> = { AsyncStream { $0.finish() } },
    pushTokenChanged: @escaping @Sendable () async -> Void = {}
  ) {
    self.device = device
    self.play = play
    self.nameCat = nameCat
    self.react = react
    self.deliver = deliver
    self.updates = updates
    self.pushTokenChanged = pushTokenChanged
  }

  /// Delivery through the room socket at `url`, while the app is open.
  public static func live(url: URL, device: String) -> NoteDelivery {
    let socket = LiveDelivery(url: url)
    return NoteDelivery(
      device: device,
      deliver: { await socket.send($0, id: $1) },
      play: { await socket.play($0, at: $1) },
      nameCat: { await socket.nameCat($0) },
      react: { await socket.react(to: $0, $1) },
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
  public static let localFake = NoteDelivery { _, _ in }
}
