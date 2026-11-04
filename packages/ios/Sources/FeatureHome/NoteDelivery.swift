import DesignSystem
import FeatureInbox
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
    /// Events of the cat's life, from the room's log or carried by another frame.
    case life([LifeEvent])
    /// The room's table of treats: day to the devices that gave one.
    case treats([String: Set<String>])
    /// The name the room holds for the cat.
    case catName(String)
    /// Where the room's light switch stands, from either partner's last press.
    case roomLight(RoomLight)
    /// Where a room's furniture stands, from either partner's last arrangement of it.
    case roomArranged(RoomArrangement)
    /// The room's table of reactions: note to the reaction its receiver sent.
    case reactions([UUID: Reaction])
    /// A note from the partner that stays closed until `opensAt`. Only the fake partner sends
    /// these for now: the room has no frame for them.
    case sealedNote([Stroke], id: UUID, opensAt: Date)
    /// The colour of the partner's lamp. Only the fake partner says this for now: the room has no
    /// frame for it.
    case partnerGlow(PartnerGlow)
    /// A wrapped gift on this phone's doormat. Only the fake partner sends these for now.
    case gift(id: UUID, item: String)
    /// The partner unwrapped a gift this phone sent.
    case giftOpened(UUID)
    /// The partner drew behind advent door `number` for this phone. Only the fake partner does.
    case adventDoor(Int, [Stroke])
    /// The partner's move while the pair chooses its cat.
    case partnerAdoption(AdoptionMove)
    /// The room's prompts of the drawing of the day, for each day a phone may be living now.
    case dailyPrompts([String: DailyPromptText])
    /// What the room lets this phone see of one day of the drawing of the day.
    case daily(DailyEntry)
  }

  /// This device's ID, to tell its own treats from the partner's.
  public var device: String
  /// Sends a drawing under `id`, which is also the ID of the note the partner receives.
  public var deliver: @Sendable ([Stroke], UUID) async -> Void
  /// Tells the partner's phone about a pet or a treat. `at` is an ISO time in the sender's calendar.
  public var play: @Sendable (PlayKind, _ at: String) async -> Void
  /// Tells the room about an event of the cat's life that this phone made. A note's event is
  /// carried by the note, so only the other kinds come through here.
  public var life: @Sendable (LifeEvent) async -> Void
  /// Names the cat. The room keeps the first name from either partner.
  public var nameCat: @Sendable (String) async -> Void
  /// Names the cat over any name it had: the last name given wins on both phones.
  public var renameCat: @Sendable (String) async -> Void
  /// Tells the room where this phone's light switch now stands: the last press wins on both
  /// phones.
  public var switchLight: @Sendable (RoomLight) async -> Void
  /// Tells the room where this phone has arranged a room's furniture: the last arrangement of
  /// each room wins on both phones.
  public var arrange: @Sendable (RoomArrangement) async -> Void
  /// Tells the partner this phone's move while the pair chooses its cat.
  public var adopt: @Sendable (AdoptionMove) async -> Void
  /// Sends a reaction to a note the partner sent.
  public var react: @Sendable (_ note: UUID, Reaction) async -> Void
  /// Sends this phone's drawing of the day. `at` is an ISO time in the sender's calendar, whose
  /// day is the one drawn.
  public var drawDaily: @Sendable ([Stroke], _ at: String) async -> Void
  /// Tells the partner something an experiment needs and the room has no frame for. Left as it is,
  /// it sends nothing.
  public var signal: @Sendable (LabSignal) async -> Void
  /// Holds the connection open for as long as the stream is being read.
  public var updates: @Sendable () -> AsyncStream<Update>
  public var pushTokenChanged: @Sendable () async -> Void

  public init(
    device: String = "",
    deliver: @escaping @Sendable ([Stroke], UUID) async -> Void,
    play: @escaping @Sendable (PlayKind, String) async -> Void = { _, _ in },
    life: @escaping @Sendable (LifeEvent) async -> Void = { _ in },
    nameCat: @escaping @Sendable (String) async -> Void = { _ in },
    renameCat: @escaping @Sendable (String) async -> Void = { _ in },
    switchLight: @escaping @Sendable (RoomLight) async -> Void = { _ in },
    arrange: @escaping @Sendable (RoomArrangement) async -> Void = { _ in },
    adopt: @escaping @Sendable (AdoptionMove) async -> Void = { _ in },
    react: @escaping @Sendable (UUID, Reaction) async -> Void = { _, _ in },
    drawDaily: @escaping @Sendable ([Stroke], String) async -> Void = { _, _ in },
    signal: @escaping @Sendable (LabSignal) async -> Void = { _ in },
    updates: @escaping @Sendable () -> AsyncStream<Update> = { AsyncStream { $0.finish() } },
    pushTokenChanged: @escaping @Sendable () async -> Void = {}
  ) {
    self.device = device
    self.play = play
    self.life = life
    self.nameCat = nameCat
    self.renameCat = renameCat
    self.switchLight = switchLight
    self.arrange = arrange
    self.adopt = adopt
    self.react = react
    self.drawDaily = drawDaily
    self.signal = signal
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
      life: { await socket.life($0) },
      nameCat: { await socket.nameCat($0) },
      renameCat: { await socket.renameCat($0) },
      switchLight: { await socket.switchLight($0) },
      arrange: { await socket.arrange($0) },
      adopt: { await socket.adopt($0) },
      react: { await socket.react(to: $0, $1) },
      drawDaily: { await socket.drawDaily($0, at: $1) },
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
