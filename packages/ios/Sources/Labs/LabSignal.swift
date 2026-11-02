import Foundation
import Wire

/// Something this phone tells the partner that the room has no frame for. Delivery over the real
/// room ignores these, so nothing reaches a real partner.
public enum LabSignal: Hashable, Sendable {
  /// This phone's lamp went out (`false`) or came back on (`true`).
  case lamp(on: Bool)
  /// This phone wrapped the item `item` and put it on the partner's doormat.
  case gift(id: UUID, item: String)
  /// This phone unwrapped the gift `id`.
  case giftOpened(id: UUID)
  /// This phone drew behind advent door `number` for the partner.
  case adventDoor(number: Int, strokes: [Stroke])
}
