import Foundation

/// Something this phone tells the partner that the room has no frame for. Delivery over the real
/// room ignores these, so nothing reaches a real partner.
public enum LabSignal: Hashable, Sendable {
  /// This phone's lamp went out (`false`) or came back on (`true`).
  case lamp(on: Bool)
}
