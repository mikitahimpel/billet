import Foundation
import Observation
import Transport
import WidgetBridge
import Wire

/// Which of Mochi's rooms this pair's Home offers: the `rooms` experiment, a Labs choice on this phone, or both.
///
/// The server's answer replaces the kept copy on every read and is saved, so it is there at the next launch and
/// offline. A phone without a partner, or one the server said nothing to, has both rooms.
@MainActor
@Observable
final class RoomsChoice {
    static let remoteKey = "remote-flags"
    static let labsKey = "labs.rooms"

    private(set) var remote: RemoteFlags
    /// Set from Labs to look at a variant on purpose; nil follows the test.
    var labs: RoomsVariant? {
        didSet { defaults.set(labs?.remoteVariant, forKey: Self.labsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        remote = defaults.data(forKey: Self.remoteKey).flatMap { try? JSONDecoder().decode(RemoteFlags.self, from: $0) }
            ?? RemoteFlags()
        labs = defaults.string(forKey: Self.labsKey).flatMap(RoomsVariant.init(remoteVariant:))
    }

    var variant: RoomsVariant { RoomsVariant.resolved(labs: labs, remote: remote) }

    /// Asks the server for the pair's variants. A failed request changes nothing.
    func refresh(_ api: APIClient) async {
        guard let response = try? await api.flags() else { return }
        let assignments = Dictionary(response.flags.map { ($0.key, $0.variant) }, uniquingKeysWith: { first, _ in first })
        set(RemoteFlags(assignments: assignments))
    }

    /// Forgets the pair's variants, for a phone that has no partner: they belong to the pair.
    func forget() { set(RemoteFlags()) }

    private func set(_ flags: RemoteFlags) {
        guard flags != remote else { return }
        remote = flags
        defaults.set(try? JSONEncoder().encode(flags), forKey: Self.remoteKey)
    }
}

extension RoomKind {
    init(_ room: NookiRoom) {
        switch room {
        case .room: self = .home
        case .city: self = .city
        }
    }

    /// The word `RoomOpened` carries.
    var eventDetail: String {
        switch self {
        case .home: "room"
        case .city: "city"
        }
    }
}

extension RoomsVariant {
    /// The rooms Home offers, as Home names them.
    var kinds: [RoomKind] { rooms.map(RoomKind.init) }

    /// How Labs names it.
    var title: String {
        switch self {
        case .both: "Both rooms"
        case .roomOnly: "Room only"
        case .cityOnly: "City only"
        }
    }
}
