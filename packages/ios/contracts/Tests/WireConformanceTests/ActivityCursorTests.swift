import Foundation
import Testing

@testable import Wire

@Suite struct ActivityCursorTests {
  @Test func anItemsCursorIsThePagesNextForItsLastItem() throws {
    let url = fixturesDirectory.appending(path: "ActivityResponse/default.json")
    let response = try JSONDecoder().decode(ActivityResponse.self, from: Data(contentsOf: url))
    let last = try #require(response.items.last)
    #expect(last.cursor == response.next)
  }
}
