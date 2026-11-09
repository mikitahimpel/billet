import Foundation
import Testing
import WidgetBridge
@testable import Billet

/// Which rooms Home offers for the `rooms` experiment, and what this phone keeps of it.
struct RoomsChoiceTests {
    private func defaults() -> UserDefaults {
        let name = "rooms-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func aPhoneTheServerSaidNothingToHasBothRooms() {
        let rooms = RoomsChoice(defaults: defaults())
        #expect(rooms.variant == .both)
        #expect(rooms.variant.kinds == [.home, .city])
    }

    @Test func eachVariantMapsToHomesRooms() {
        #expect(RoomsVariant.both.kinds == [.home, .city])
        #expect(RoomsVariant.roomOnly.kinds == [.home])
        #expect(RoomsVariant.cityOnly.kinds == [.city])
    }

    @Test func roomOpenedNamesTheRoom() {
        #expect(RoomKind.home.eventDetail == "room")
        #expect(RoomKind.city.eventDetail == "city")
    }

    @Test func aLabsChoiceIsKeptAndWins() {
        let store = defaults()
        RoomsChoice(defaults: store).labs = .cityOnly
        let again = RoomsChoice(defaults: store)
        #expect(again.labs == .cityOnly)
        #expect(again.variant == .cityOnly)
        again.labs = nil
        #expect(RoomsChoice(defaults: store).variant == .both)
    }

    @Test func thePairsVariantIsKeptForTheNextLaunch() throws {
        let store = defaults()
        let flags = RemoteFlags(assignments: ["rooms": "room-only"])
        store.set(try JSONEncoder().encode(flags), forKey: RoomsChoice.remoteKey)
        #expect(RoomsChoice(defaults: store).variant == .roomOnly)
    }

    @Test func forgettingThePairGoesBackToBoth() throws {
        let store = defaults()
        store.set(try JSONEncoder().encode(RemoteFlags(assignments: ["rooms": "city-only"])), forKey: RoomsChoice.remoteKey)
        let rooms = RoomsChoice(defaults: store)
        rooms.forget()
        #expect(rooms.variant == .both)
        #expect(RoomsChoice(defaults: store).variant == .both)
    }
}
