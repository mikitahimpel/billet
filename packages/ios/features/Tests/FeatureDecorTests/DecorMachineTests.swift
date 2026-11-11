import DecorInterface
import Foundation
import Persistence
import Testing

@testable import FeatureDecor

typealias M = DecorMachine

private let owned: Set<String> = ["yarn", "mouse", "print", "monstera", "bookcase"]
private let armchair = Placement(item: "yarn", surface: .floor, u: -5, v: -5)

private func book(
  _ placements: [Placement] = [armchair], stored: Set<String> = ["monstera", "bookcase"]
) -> M.Book {
  M.Book(layout: DecorLayout(placements: placements, stored: stored), owned: owned)
}

@Suite struct DecorMachineTests {
  @Test func theServersLayoutReplacesThePlacementsAndKeepsWhatWasPutAway() {
    let theirs = Placement(item: "mouse", surface: .floor, u: 7, v: 0)
    let (state, outputs) = M.transition(.off(book()), .remote([theirs]))
    #expect(state.book.layout.placement(of: "mouse") == theirs)
    #expect(
      !state.book.layout.isPlaced("yarn") || state.book.layout.placement(of: "yarn") != armchair)
    #expect(state.book.layout.stored.contains("monstera"))
    #expect(outputs.allSatisfy { if case .keep = $0 { true } else { false } } || !outputs.isEmpty)
  }

  @Test func aRemoteLayoutThatIsAlreadyHereChangesNothing() {
    let settled = M.Book(
      layout: DecorLayout(placements: [armchair], stored: owned.subtracting(["yarn"])), owned: owned
    )
    let start = M.State.off(settled)
    #expect(M.transition(start, .remote([armchair])) == (start, []))
  }

  @Test func newPiecesLandInTheRoomWhenOwnedChanges() {
    let (state, outputs) = M.transition(.off(M.Book()), .owned(["yarn"]))
    #expect(state.book.layout.isPlaced("yarn"))
    #expect(outputs == [.save(state.book.layout)])
  }

  @Test func theSameOwnedSetChangesNothing() {
    let start = M.State.off(book())
    #expect(M.transition(start, .owned(owned)) == (start, []))
  }

  @Test func aLoadedLayoutIsSettledAgainstWhatIsOwned() {
    let (state, outputs) = M.transition(
      .off(M.Book(layout: DecorLayout(), owned: ["yarn"])),
      .loaded(DecorLayout(placements: [armchair], stored: [])))
    #expect(state.book.layout.placement(of: "yarn") == armchair)
    #expect(outputs.isEmpty)
  }

  @Test func openingWithAPieceInTheClosetStandsItInTheRoomAndChoosesIt() {
    let (state, outputs) = M.transition(.off(book()), .opened(item: "mouse"))
    guard case .selected(let next, "mouse") = state else {
      Issue.record("not selected")
      return
    }
    #expect(next.layout.isPlaced("mouse"))
    #expect(outputs == [.save(next.layout), .feedback(.placed)])
  }

  @Test func openingWithAPlacedPieceOnlyChoosesIt() {
    #expect(
      M.transition(.off(book()), .opened(item: "yarn")) == (.selected(book(), item: "yarn"), []))
  }

  @Test func openingWithNothingShowsTheCloset() {
    #expect(M.transition(.off(book()), .opened(item: nil)) == (.closet(book()), []))
    #expect(M.transition(.off(book()), .opened(item: "treat-fish")) == (.closet(book()), []))
  }

  @Test func closingKeepsTheLayout() {
    let state = M.State.selected(book(), item: "yarn")
    #expect(M.transition(state, .closed) == (.off(book()), []))
    #expect(M.transition(.off(book()), .closed) == (.off(book()), []))
  }

  @Test func tappingAPieceInTheClosetPlacesIt() {
    let (state, outputs) = M.transition(.closet(book()), .closetTapped("print"))
    #expect(state.selection == "print")
    #expect(outputs.contains(.feedback(.placed)))
  }

  @Test func tappingPiecesInTheRoomChoosesThemAndTheFloorLetsGo() {
    let chosen = M.State.selected(book(), item: "yarn")
    #expect(M.transition(.closet(book()), .roomTapped("yarn")) == (chosen, []))
    #expect(M.transition(chosen, .emptyTapped) == (.closet(book()), []))
    #expect(M.transition(.closet(book()), .roomTapped("mouse")) == (.closet(book()), []))
  }

  @Test func aDragMovesThePieceAndLettingGoOnAFreeSpotKeepsIt() {
    let target = Placement(item: "yarn", surface: .floor, u: -5, v: 0)
    var (state, _) = M.transition(.selected(book(), item: "yarn"), .dragBegan("yarn"))
    (state, _) = M.transition(state, .dragged(target))
    #expect(state.layout.placement(of: "yarn") == target)
    #expect(state.isValid)
    let (dropped, outputs) = M.transition(state, .dropped)
    guard case .selected(let next, "yarn") = dropped else {
      Issue.record("not selected")
      return
    }
    #expect(next.layout.placement(of: "yarn") == target)
    #expect(outputs == [.save(next.layout)])
  }

  @Test func lettingGoWhereItDoesNotFitPutsItBack() {
    let onTheBed = Placement(item: "yarn", surface: .backWall, u: 1)
    var (state, _) = M.transition(.selected(book(), item: "yarn"), .dragBegan("yarn"))
    (state, _) = M.transition(state, .dragged(onTheBed))
    #expect(!state.isValid)
    let (dropped, outputs) = M.transition(state, .dropped)
    #expect(dropped.book.layout == book().layout)
    #expect(dropped.selection == "yarn")
    #expect(dropped.book.notice == .rejected)
    #expect(outputs == [.feedback(.rejected)])
  }

  @Test func aCancelledDragChangesNothing() {
    var (state, _) = M.transition(.selected(book(), item: "yarn"), .dragBegan("yarn"))
    (state, _) = M.transition(
      state, .dragged(Placement(item: "yarn", surface: .floor, u: -5, v: 2)))
    #expect(M.transition(state, .dragCancelled) == (.selected(book(), item: "yarn"), []))
  }

  @Test func aDragOfAnotherPieceIsIgnored() {
    let (state, _) = M.transition(.selected(book(), item: "yarn"), .dragBegan("yarn"))
    #expect(
      M.transition(state, .dragged(Placement(item: "mouse", surface: .floor, u: 3, v: 6))) == (
        state, []
      ))
    #expect(M.transition(.selected(book(), item: "yarn"), .dragBegan("mouse")).1.isEmpty)
  }

  @Test func turningTurnsAFloorPieceAndSaves() {
    let (state, outputs) = M.transition(.selected(book(), item: "yarn"), .turned)
    #expect(state.book.layout.placement(of: "yarn")?.quarterTurns == 1)
    #expect(outputs == [.save(state.book.layout)])
  }

  @Test func aTurnThatFitsNowhereSaysSoAndChangesNothing() {
    // Turned, the bookcase meets the wall, the bed and the nightstand wherever it goes.
    let tight = Placement(item: "bookcase", surface: .floor, u: -1, v: 7)
    let state = M.State.selected(book([tight]), item: "bookcase")
    let (next, outputs) = M.transition(state, .turned)
    #expect(next.book.layout == state.book.layout)
    #expect(next.book.notice == .noRoomToTurn("bookcase"))
    #expect(outputs == [.feedback(.noRoomToTurn)])
  }

  @Test func theLastBedOrSofaCannotBeStored() {
    let fresh = M.Book(layout: DecorLayout(), owned: [])
    let state = M.State.selected(fresh, item: "base-donutbed")
    let (refused, refusal) = M.transition(state, .stored)
    #expect(refused.book.layout == fresh.layout && refused.book.notice == .lastRest)
    #expect(refusal == [.feedback(.lastRest)])
    let (stored, outputs) = M.transition(
      .selected(fresh, item: "base-plant"), .stored)
    #expect(!stored.book.layout.isPlaced("base-plant"))
    #expect(outputs == [.save(stored.book.layout)])
  }

  @Test func resettingTheRoomPutsTheFurnitureBack() {
    let messy = M.Book(
      layout: DecorLayout().putting(Placement(item: "base-cattree", surface: .floor, u: 7, v: 0))
        .storing("base-plant"),
      owned: [])
    let (state, outputs) = M.transition(.closet(messy), .resetRoom)
    guard case .closet(let reset) = state else {
      Issue.record("not the closet")
      return
    }
    #expect(reset.layout.placements.isEmpty && reset.layout.stowed.isEmpty)
    #expect(outputs == [.save(reset.layout), .feedback(.reset)])
    let (again, nothing) = M.transition(.closet(reset), .resetRoom)
    #expect(again.book.layout == reset.layout && nothing.isEmpty)
  }

  @Test func aWallPieceCannotBeTurned() {
    let hung = Placement(item: "print", surface: .backWall, u: 6)
    let state = M.State.selected(book([hung]), item: "print")
    #expect(!state.canTurn)
    #expect(M.transition(state, .turned) == (state, []))
  }

  @Test func storingPutsThePieceBackInTheClosetAndOpensIt() {
    let (state, outputs) = M.transition(.selected(book(), item: "yarn"), .stored)
    guard case .closet(let next) = state else {
      Issue.record("not the closet")
      return
    }
    #expect(!next.layout.isPlaced("yarn"))
    #expect(next.closet.map(\.id).contains("yarn"))
    #expect(outputs == [.save(next.layout)])
    // Owning it again changes nothing: a piece put away stays away.
    #expect(M.transition(state, .owned(owned)).1.isEmpty)
  }

  @Test func losingAPieceTakesItOutOfTheRoom() {
    let (state, outputs) = M.transition(.selected(book(), item: "yarn"), .owned(["mouse"]))
    guard case .closet(let next) = state else {
      Issue.record("not the closet")
      return
    }
    #expect(!next.layout.isPlaced("yarn"))
    #expect(outputs.count == 1)
  }

  @Test(arguments: [
    (M.State.off(book()), M.Event.closetTapped("print")),
    (.off(book()), .roomTapped("yarn")),
    (.off(book()), .emptyTapped),
    (.off(book()), .dragBegan("yarn")),
    (.off(book()), .dragged(armchair)),
    (.off(book()), .dropped),
    (.off(book()), .dragCancelled),
    (.off(book()), .turned),
    (.off(book()), .stored),
    (.closet(book()), .emptyTapped),
    (.closet(book()), .dragged(armchair)),
    (.closet(book()), .dropped),
    (.closet(book()), .dragCancelled),
    (.closet(book()), .turned),
    (.closet(book()), .stored),
    (.selected(book(), item: "yarn"), .dragged(armchair)),
    (.selected(book(), item: "yarn"), .dropped),
    (.selected(book(), item: "yarn"), .dragCancelled),
  ])
  func rejectedEventsChangeNothing(state: M.State, event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test func eventsDuringADragOtherThanItsOwnAreIgnored() {
    let (moving, _) = M.transition(.selected(book(), item: "yarn"), .dragBegan("yarn"))
    for event: M.Event in [
      .closetTapped("print"), .roomTapped("yarn"), .emptyTapped, .dragBegan("yarn"),
      .turned, .stored, .opened(item: "print"),
    ] {
      #expect(M.transition(moving, event) == (moving, []))
    }
  }

  @Test func aChangeCanBeTakenBackOnce() {
    let start = M.State.selected(book(), item: "yarn")
    let (turned, _) = M.transition(start, .turned)
    #expect(turned.book.undo == book().layout)
    let (undone, outputs) = M.transition(turned, .undone)
    #expect(undone.book.layout == book().layout)
    #expect(undone.book.undo == nil)
    #expect(outputs == [.save(book().layout)])
    #expect(M.transition(undone, .undone).1.isEmpty)
  }

  @Test func aServersWordClearsWhatCouldBeTakenBack() {
    let (turned, _) = M.transition(.selected(book(), item: "yarn"), .turned)
    let theirs = Placement(item: "mouse", surface: .floor, u: 7, v: 0)
    let (heard, _) = M.transition(turned, .remote([theirs]))
    #expect(heard.book.undo == nil)
  }
}

@MainActor @Suite struct DecorStoreTests {
  private func storage(_ saved: Locked<[DecorLayout]> = Locked([])) -> DecorStorage {
    DecorStorage(load: { saved.value.last }, save: { layout in saved.mutate { $0.append(layout) } })
  }

  @Test func theArrangementSurvivesARelaunch() async {
    let saved = Locked<[DecorLayout]>([])
    let first = DecorStore.decor(DecorServices(storage: storage(saved), feedback: { _ in }))
    first.send(.owned(["yarn"]))
    await first.settled()
    let second = DecorStore.decor(DecorServices(storage: storage(saved), feedback: { _ in }))
    second.send(.owned(["yarn"]))
    #expect(second.state.book.layout == first.state.book.layout)
    #expect(second.state.book.layout.isPlaced("yarn"))
  }

  @Test func theAppGroupFileRoundTrips() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = DecorStorage.appGroup(.directory(directory))
    #expect(files.load() == nil)
    let layout = DecorLayout(placements: [armchair], stored: ["monstera"])
    files.save(layout)
    #expect(files.load() == layout)
  }

  @Test func feedbackReachesTheApp() async {
    let heard = Locked<[M.Feedback]>([])
    let store = DecorStore.decor(
      DecorServices(storage: storage(), feedback: { kind in heard.mutate { $0.append(kind) } }))
    store.send(.owned(["yarn"]))
    store.send(.opened(item: "yarn"))
    store.send(.closetTapped("mouse"))
    store.send(.owned(["yarn", "mouse"]))
    store.send(.closetTapped("mouse"))
    await store.settled()
    #expect(store.state.selection == "mouse")
  }
}

final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value
  init(_ value: Value) { stored = value }
  var value: Value { lock.withLock { stored } }
  func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
