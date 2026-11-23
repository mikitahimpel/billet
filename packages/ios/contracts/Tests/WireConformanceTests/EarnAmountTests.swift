import Foundation
import Testing

@testable import Wire

/// The amounts the app promises on its labels are the ones the server pays, from
/// `packages/contracts/fixtures/rewards.json` (written by the fixtures package from `coins.ts` and `shop.ts`).
@Suite struct EarnAmountTests {
  private struct Rewards: Decodable {
    let earn: [String: Int]
    let collections: [String: Int]
  }

  private static func load() throws -> Rewards {
    let url =
      fixturesDirectory
      .deletingLastPathComponent()
      .appending(path: "rewards.json")
    return try JSONDecoder().decode(Rewards.self, from: Data(contentsOf: url))
  }

  @Test func theAppPromisesWhatTheServerPays() throws {
    let rewards = try Self.load()
    let app: [String: Int] = [
      "moment": EarnAmount.moment,
      "note": EarnAmount.note,
      "dateMatched": EarnAmount.dateMatched,
      "dateRated": EarnAmount.dateRated,
      "wishReceived": EarnAmount.wishReceived,
      "listTicked": EarnAmount.listTicked,
      "roundPlayed": EarnAmount.roundPlayed,
      "guessHit": EarnAmount.guessHit,
    ]
    #expect(app == rewards.earn)
  }

  @Test func theAppShowsTheCollectionBonusesTheServerPays() throws {
    #expect(EarnAmount.collectionBonus == (try Self.load()).collections)
  }
}
