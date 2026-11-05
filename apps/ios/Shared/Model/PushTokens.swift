import Foundation

/// The APNs tokens this phone has been given, kept in the App Group so the widget extension can hand its token to the
/// app, which registers them with the server. `registered` remembers what the server already has.
nonisolated struct PushTokens: Codable, Hashable, Sendable {
    var alert: String?
    var widget: String?
    var registeredAlert: String?
    var registeredWidget: String?
    /// The token the server starts the drawing Live Activity with (push-to-start), and the one it already has.
    var liveActivity: String?
    var registeredLiveActivity: String?

    static let path = "Push/tokens.json"

    static func load() -> PushTokens { SharedFile.read(PushTokens.self, from: path) ?? PushTokens() }

    static func save(alert token: String) { update { $0.alert = token } }
    static func save(widget token: String) { update { $0.widget = token } }
    static func save(liveActivity token: String) { update { $0.liveActivity = token } }

    static func update(_ change: (inout PushTokens) -> Void) {
        var tokens = load()
        change(&tokens)
        SharedFile.write(tokens, to: path)
        SharedFile.flush()
    }
}
