public enum PushTokenKind: String, Codable, Hashable, Sendable {
  case alert
  case widget
  /// The device's push-to-start token for the drawing Live Activity.
  case liveactivity
}
