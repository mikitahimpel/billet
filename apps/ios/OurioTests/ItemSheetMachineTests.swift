import Testing
@testable import Billet

@Suite struct ItemSheetMachineTests {
    typealias Machine = ItemSheetMachine

    @Test func aBuyKeepsTheSheetOpenOnPlaceNow() {
        #expect(Machine.transition(.previewing, .bought) == (.bought, []))
    }

    @Test func placeNowOpensTheRoomAndClosesTheSheet() {
        #expect(Machine.transition(.bought, .placeNowTapped) == (.closed, [.openRoom, .close]))
    }

    @Test func notNowJustCloses() {
        #expect(Machine.transition(.bought, .notNowTapped) == (.closed, [.close]))
    }

    @Test func shortOfCoinsGivesWayToTheCoinsSheet() {
        #expect(Machine.transition(.previewing, .coinsAsked) == (.closed, [.close]))
    }

    @Test func anOwnedItemOpensOnPlaceNow() {
        #expect(Machine.initial(owned: true) == .bought)
        #expect(Machine.initial(owned: false) == .previewing)
    }

    @Test(arguments: [
        (Machine.State.previewing, Machine.Event.placeNowTapped),
        (.previewing, .notNowTapped),
        (.bought, .bought),
        (.bought, .coinsAsked),
        (.closed, .bought),
        (.closed, .placeNowTapped),
        (.closed, .notNowTapped),
        (.closed, .coinsAsked),
    ])
    func rejectedEventsChangeNothing(state: Machine.State, event: Machine.Event) {
        let (next, outputs) = Machine.transition(state, event)
        #expect(next == state)
        #expect(outputs.isEmpty)
    }
}
