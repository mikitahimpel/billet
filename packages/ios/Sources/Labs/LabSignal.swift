import Foundation
import Wire

/// Something this phone tells the partner for an experiment. The real room carries gifts and
/// their opening; it has no frame for the rest, so those reach only the fake partner.
public enum LabSignal: Hashable, Sendable {
  /// This phone's lamp went out (`false`) or came back on (`true`).
  case lamp(on: Bool)
  /// This phone wrapped the item `item` and put it on the partner's doormat, with a note.
  case gift(id: UUID, item: String, note: String? = nil)
  /// This phone unwrapped the gift `id`.
  case giftOpened(id: UUID)
  /// This phone drew behind advent door `number` for the partner.
  case adventDoor(number: Int, strokes: [Stroke])
}
