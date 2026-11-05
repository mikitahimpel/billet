import Foundation
import Wire

nonisolated extension PushPayload {
    /// The key under a push's custom data that holds a `PushPayload` (packages/contracts/push).
    static let pushKey = "billet"

    /// The payload in a push's custom data, or nil when it has none.
    init?(push userInfo: [AnyHashable: Any]) {
        guard let object = userInfo[Self.pushKey], JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let payload = try? JSONDecoder().decode(PushPayload.self, from: data) else { return nil }
        self = payload
    }

    /// The alert's body to show under the partner's name, which the server does not know; nil keeps the server's.
    var bodyAfterName: String? {
        switch self {
        case .reaction(_, _, let reaction): "Reacted \(reaction.emoji) to your photo"
        case .alert(_, _, nil, nil, _): "Sent you a photo"
        case .alert, .widget, .liveActivity: nil
        }
    }
}
