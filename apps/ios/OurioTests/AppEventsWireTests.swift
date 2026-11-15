import Foundation
import GamesInterface
import ShopInterface
import UsInterface
import Testing
import Transport
import Wire
@testable import Billet

@MainActor
@Suite(.serialized) struct AppEventsWireTests {
    @MainActor final class Heard {
        var events: [ClientEvent] = []
    }

    private let heard = Heard()
    private var reporter: EventReporter {
        let heard = heard
        return EventReporter { heard.events.append($0) }
    }

    private func care() -> CatCare {
        CatCare(
            wallet: WalletStore(file: "Tests/\(UUID().uuidString)-wallet.json"),
            streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"), events: reporter)
    }

    @Test func aPetInTheAppAndOneFromAWidgetAreCountedApart() {
        let care = care()
        care.pet()
        care.pet(fromWidget: true)
        #expect(heard.events == [ClientEvent(.catPetted), ClientEvent(.widgetButtonTapped, detail: "pet")])
    }

    @Test func aTreatIsTheTreatAndWeighingFoodIsFood() {
        let care = care()
        care.fed()
        care.played(.feed)
        #expect(heard.events == [ClientEvent(.catFed, detail: "treat"), ClientEvent(.catFed, detail: "food")])
    }

    @Test(arguments: [MiniGame.water, .laser, .brush])
    func aGameIsPlayedByItsId(_ game: MiniGame) {
        care().played(game)
        #expect(heard.events == [ClientEvent(.catPlayed, detail: game.rawValue)])
        #expect(heard.events.allSatisfy { $0.problem == nil })
    }

    @Test func theProfileIsCountedEachTimeItOpens() {
        let state = HomeState(stores: .live(events: reporter))
        state.showsProfile = true
        state.showsProfile = true
        state.showsProfile = false
        state.showsProfile = true
        #expect(heard.events == [ClientEvent(.profileOpened), ClientEvent(.profileOpened)])
    }
}
