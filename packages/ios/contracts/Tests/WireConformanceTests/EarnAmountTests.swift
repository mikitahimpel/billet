import Foundation
import Testing

@testable import Wire

/// The amounts the app promises on its buttons are the ones the server pays.
@Suite struct EarnAmountTests {
  private static let coinsTS =
    fixturesDirectory
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "domain/src/coins.ts")

  @Test func theAppPromisesWhatTheServerPays() throws {
    let source = try String(contentsOf: Self.coinsTS, encoding: .utf8)
    #expect(source.contains("of(\"moment\", event.moment, \(EarnAmount.moment), \"notes\")"))
    #expect(source.contains("of(\"note\", event.note, \(EarnAmount.note), \"notes\")"))
    #expect(source.contains("of(\"date\", event.idea, \(EarnAmount.dateMatched))"))
  }
}
