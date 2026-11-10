import Foundation
import Wire

nonisolated extension PushPayload {
    /// The alert's body to show under the partner's name, which the server does not know; nil keeps the server's.
    public var bodyAfterName: String? {
        switch self {
        case .reaction(_, _, let reaction): "Reacted \(reaction.emoji) to your photo"
        case .alert(_, _, nil, nil, _): "Sent you a photo"
        case .alert, .widget, .liveActivity: nil
        }
    }
}
