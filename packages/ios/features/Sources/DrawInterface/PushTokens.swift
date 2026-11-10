import Foundation
import Persistence

/// The APNs tokens this phone has been given, kept in the App Group so the widget extension can hand its token to the
/// app, which registers them with the server. `registered` remembers what the server already has.
public struct PushTokens: Codable, Hashable, Sendable {
  public var alert: String?
  public var widget: String?
  public var registeredAlert: String?
  public var registeredWidget: String?
  /// The token the server starts the drawing Live Activity with (push-to-start), and the one it already has.
  public var liveActivity: String?
  public var registeredLiveActivity: String?

  public init(
    alert: String? = nil, widget: String? = nil, registeredAlert: String? = nil,
    registeredWidget: String? = nil, liveActivity: String? = nil,
    registeredLiveActivity: String? = nil
  ) {
    self.alert = alert
    self.widget = widget
    self.registeredAlert = registeredAlert
    self.registeredWidget = registeredWidget
    self.liveActivity = liveActivity
    self.registeredLiveActivity = registeredLiveActivity
  }

  public static let path = "Push/tokens.json"

  public static func load() -> PushTokens {
    SharedFile.read(PushTokens.self, from: path) ?? PushTokens()
  }

  public static func save(alert token: String) { update { $0.alert = token } }
  public static func save(widget token: String) { update { $0.widget = token } }
  public static func save(liveActivity token: String) { update { $0.liveActivity = token } }

  public static func update(_ change: (inout PushTokens) -> Void) {
    var tokens = load()
    change(&tokens)
    SharedFile.write(tokens, to: path)
    SharedFile.flush()
  }
}
