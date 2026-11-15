import DecorInterface
import Foundation
import Testing
import Transport
import Wire

@testable import FeatureDecor

@Suite struct DecorEventsTests {
  private let lamp = Placement(item: "mouse", surface: .floor, u: 2, v: 3)

  @Test func aPieceThatComesIntoTheRoomIsPlaced() {
    let old = DecorLayout(placements: [], stored: ["mouse"])
    let new = DecorLayout(placements: [lamp], stored: [])
    #expect(new.events(since: old) == [ClientEvent(.roomItemPlaced, detail: "mouse")])
  }

  @Test func aPieceStandingElsewhereOrTurnedIsMoved() {
    let old = DecorLayout(placements: [lamp], stored: [])
    var moved = lamp
    moved.u = 4
    var turned = lamp
    turned.eighthTurns = 2
    #expect(
      DecorLayout(placements: [moved], stored: []).events(since: old) == [
        ClientEvent(.roomItemMoved, detail: "mouse")
      ])
    #expect(
      DecorLayout(placements: [turned], stored: []).events(since: old) == [
        ClientEvent(.roomItemMoved, detail: "mouse")
      ])
  }

  @Test func aPieceSentToTheClosetIsPutAway() {
    let old = DecorLayout(placements: [lamp], stored: [])
    let new = DecorLayout(placements: [], stored: ["mouse"])
    #expect(new.events(since: old) == [ClientEvent(.roomItemPutAway, detail: "mouse")])
  }

  @Test func theSameLayoutIsNothing() {
    let layout = DecorLayout(placements: [lamp], stored: [])
    #expect(layout.events(since: layout).isEmpty)
  }

  @Test func everyEventKeepsItsRule() {
    let old = DecorLayout()
    let new = DecorLayout(placements: [lamp], stored: [])
    #expect(new.events(since: old).allSatisfy { $0.problem == nil })
  }
}

@MainActor @Suite struct DecorStoreEventsTests {
  @MainActor final class Heard {
    var events: [ClientEvent] = []
  }

  @Test func onlyThePlayersOwnChangesAreCounted() async {
    let heard = Heard()
    let store = DecorStore.decor(
      DecorServices(
        storage: DecorStorage(load: { nil }, save: { _ in }), feedback: { _ in },
        events: EventReporter { heard.events.append($0) }))
    // New pieces settle into the room by themselves: not the player's doing.
    store.send(.owned(["yarn", "mouse"]))
    await store.settled()
    #expect(store.state.book.layout.isPlaced("mouse"))
    #expect(heard.events.isEmpty)

    store.send(.opened(item: "mouse"))
    store.send(.stored)
    await store.settled()
    #expect(heard.events == [ClientEvent(.roomItemPutAway, detail: "mouse")])
  }
}
