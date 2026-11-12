import Foundation
import MomentsInterface
import Testing
import UsInterface
import WidgetInterface
import WidgetUI

@testable import FeatureUs

@Suite struct ListScreenMachineTests {
  typealias Machine = ListScreenMachine

  nonisolated private static let item = UUID()

  nonisolated static let sheets: [Machine.Sheet] = [
    .rename, .confirmingDelete, .editing(itemID: item), .addingTitle, .addingPlace,
    .markingBeen(itemID: item), .openedTitle(itemID: item),
  ]

  @Test(arguments: sheets)
  func aSheetOpensOverTheRows(sheet: Machine.Sheet) {
    #expect(Machine.transition(.browsing, .open(sheet)) == (.showing(sheet), []))
  }

  @Test(arguments: sheets)
  func closingGoesBackToTheRows(sheet: Machine.Sheet) {
    #expect(Machine.transition(.showing(sheet), .closed) == (.browsing, []))
  }

  @Test(arguments: [
    (Machine.State.showing(.rename), Machine.Event.open(.addingTitle)),
    (.showing(.addingPlace), .open(.markingBeen(itemID: item))),
    (.showing(.confirmingDelete), .open(.confirmingDelete)),
    (.browsing, .closed),
  ])
  func rejectedEventsChangeNothing(state: Machine.State, event: Machine.Event) {
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test func theAddMenuOpensTheSearchOnlyWhereAListAddsByIt() {
    #expect(Machine.initial(for: .watch, adding: true) == .showing(.addingTitle))
    #expect(Machine.initial(for: .travel, adding: true) == .showing(.addingPlace))
    for kind in [ListKind.groceries, .food, .books, .bucket, .custom] {
      #expect(
        Machine.initial(for: kind, adding: true) == .browsing, "\(kind) adds in its own field")
    }
    for kind in ListKind.allCases {
      #expect(Machine.initial(for: kind, adding: false) == .browsing)
    }
  }
}
