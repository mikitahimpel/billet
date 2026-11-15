import DecorInterface
import Testing

@testable import FeatureDecor

@Suite struct DecorMachineBedroomTests {
  private func bedroom(_ layout: DecorLayout = DecorLayout(), owned: Set<String> = []) -> M.State {
    var book = M.Book(layout: layout, owned: owned)
    book.space = .bedroom
    return .closet(book)
  }

  private func at(_ id: String, _ u: Int, _ v: Int) -> Placement {
    Placement(item: id, surface: .floor, u: u, v: v, space: .bedroom)
  }

  @Test func changingRoomLetsGoOfTheChosenPieceAndOpensThatRoomsCloset() {
    let living = M.State.selected(M.Book(), item: "base-plant")
    let (state, outputs) = M.transition(living, .roomChanged(.bedroom))
    #expect(outputs.isEmpty)
    #expect(state.book.space == .bedroom)
    guard case .closet = state else {
      Issue.record("not a closet: \(state)")
      return
    }
    #expect(M.transition(.off(M.Book()), .roomChanged(.bedroom)).0 == .off(bedroomBook()))
  }

  private func bedroomBook() -> M.Book {
    var book = M.Book()
    book.space = .bedroom
    return book
  }

  @Test func eachRoomsClosetHoldsItsOwnStowedFurniture() {
    let layout = DecorLayout().storing("base-bedroom-slippers").storing("base-plant")
    #expect(M.Book(layout: layout).closet.map(\.id) == ["base-plant"])
    var book = M.Book(layout: layout)
    book.space = .bedroom
    #expect(book.closet.map(\.id) == ["base-bedroom-slippers"])
  }

  @Test func theBedroomsPieceCanBeChosenDraggedAndDropped() {
    let (chosen, _) = M.transition(bedroom(), .roomTapped("base-bedroom-bed"))
    guard case .selected = chosen else {
      Issue.record("not chosen")
      return
    }
    let (moving, _) = M.transition(chosen, .dragBegan("base-bedroom-bed"))
    let spot = at("base-bedroom-bed", 2, -3)
    let (dragged, _) = M.transition(moving, .dragged(spot))
    #expect(dragged.isValid)
    let (dropped, outputs) = M.transition(dragged, .dropped)
    #expect(dropped.book.layout.placement(of: "base-bedroom-bed") == spot)
    #expect(outputs.contains { if case .save = $0 { true } else { false } })
    #expect(dropped.book.undo != nil)
  }

  @Test func aPieceDroppedInTheOtherRoomsSpotIsRefused() {
    let (chosen, _) = M.transition(bedroom(), .roomTapped("base-bedroom-bed"))
    let (moving, _) = M.transition(chosen, .dragBegan("base-bedroom-bed"))
    let wrong = Placement(item: "base-bedroom-bed", surface: .floor, u: 1, v: -3, space: .living)
    let (dragged, _) = M.transition(moving, .dragged(wrong))
    #expect(!dragged.isValid)
    let (dropped, outputs) = M.transition(dragged, .dropped)
    #expect(outputs == [.feedback(.rejected)])
    #expect(dropped.book.layout.placement(of: "base-bedroom-bed")?.space == .bedroom)
  }

  @Test func storingKeepsABedInTheRoomAndTheClosetGivesItBack() {
    let (chosenCat, _) = M.transition(bedroom(), .roomTapped("base-bedroom-catbed"))
    let (stored, _) = M.transition(chosenCat, .stored)
    guard case .closet(let book) = stored else {
      Issue.record("not closet")
      return
    }
    #expect(book.closet.map(\.id) == ["base-bedroom-catbed"])
    let (chosenBed, _) = M.transition(stored, .roomTapped("base-bedroom-bed"))
    let (refused, outputs) = M.transition(chosenBed, .stored)
    #expect(outputs == [.feedback(.lastRest)])
    #expect(refused.book.layout.isPlaced("base-bedroom-bed"))
    let (back, _) = M.transition(stored, .closetTapped("base-bedroom-catbed"))
    #expect(back.book.layout.placement(of: "base-bedroom-catbed")?.space == .bedroom)
  }

  @Test func resetRoomRestoresTheBedroomAndLeavesTheLivingRoom() {
    let arranged = DecorLayout().putting(at("base-bedroom-bed", 2, -3)).putting(
      Placement(item: "base-cattree", surface: .floor, u: 7, v: 0))
    let (state, outputs) = M.transition(bedroom(arranged), .resetRoom)
    #expect(
      state.book.layout.placement(of: "base-bedroom-bed")
        == DecorLayout().placement(of: "base-bedroom-bed"))
    #expect(state.book.layout.placement(of: "base-cattree")?.u == 7)
    #expect(outputs.contains(.feedback(.reset)))
    let (undone, _) = M.transition(state, .undone)
    #expect(undone.book.layout.placement(of: "base-bedroom-bed")?.u == 2)
  }
}
