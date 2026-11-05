import Foundation

/// Where a tap on a widget lands in the app, as a nooki:// URL. An invite also comes as the server's
/// `https://<host>/i/<code>` Universal Link.
enum DeepLink: Hashable {
    case room, moments, us, calendar, dates, newNote, draw, inbox
    case list(UUID)
    case invite(String)
    /// The Shop at an ink, by its catalog id.
    case shopInk(String)

    static let scheme = "nooki"

    var url: URL {
        let path = switch self {
        case .room: "room"
        case .moments: "moments"
        case .us: "us"
        case .calendar: "us/calendar"
        case .dates: "us/dates"
        case .newNote: "notes/new"
        case .draw: "draw"
        case .inbox: "inbox"
        case .list(let id): "us/list/\(id.uuidString)"
        case .invite(let code): "invite/\(code)"
        case .shopInk(let id): "shop/ink/\(id)"
        }
        return URL(string: "\(Self.scheme)://\(path)")!
    }

    init?(url: URL) {
        let path = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "https", path.count == 2, path[0] == "i" {
            self = .invite(path[1])
            return
        }
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let parts = [host] + url.pathComponents.filter { $0 != "/" }
        switch parts {
        case ["room"]: self = .room
        case ["moments"]: self = .moments
        case ["us"]: self = .us
        case ["us", "calendar"]: self = .calendar
        case ["us", "dates"]: self = .dates
        case ["notes", "new"]: self = .newNote
        case ["draw"]: self = .draw
        case ["inbox"]: self = .inbox
        case let p where p.count == 2 && p[0] == "invite": self = .invite(p[1])
        case let p where p.count == 3 && p[0] == "shop" && p[1] == "ink": self = .shopInk(p[2])
        case let p where p.count == 3 && p[0] == "us" && p[1] == "list":
            guard let id = UUID(uuidString: p[2]) else { return nil }
            self = .list(id)
        default: return nil
        }
    }
}
