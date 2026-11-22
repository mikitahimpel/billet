import Foundation
import Testing

@testable import StoryInterface

@Suite struct EpisodeCatalogTests {
  @Test func everyShippedEpisodeLoadsAndValidates() throws {
    #expect(!EpisodeCatalog.files.isEmpty)
    for name in EpisodeCatalog.files {
      let episode = try EpisodeCatalog.load(name)
      #expect(episode.id == name)
    }
    #expect(EpisodeCatalog.all.count == EpisodeCatalog.files.count)
  }

  @Test func theFishPlushHasFiveBeatsAndThreeSuspects() throws {
    let episode = try EpisodeCatalog.load("fish-plush")
    #expect(episode.beats.count == 5)
    #expect(episode.suspects.map(\.id) == ["vacuum", "crow", "draft"])
    #expect(episode.culprit == "crow")
  }

  @Test func theWritingNamesNobodyByPronoun() throws {
    let episode = try EpisodeCatalog.load("fish-plush")
    let text =
      episode.beats.flatMap { $0.halves.map(\.text) + [$0.together] } + episode.ending.lines
    for line in text {
      let words = line.lowercased().split { !$0.isLetter }.map(String.init)
      #expect(Set(words).isDisjoint(with: ["she", "her", "he", "him", "his", "hers"]), "\(line)")
    }
  }

  @Test func theCatAndPartnerAreFilledIn() {
    #expect(Episode.filled("{cat} and {partner}", cat: "Mochi", partner: "Leo") == "Mochi and Leo")
  }

  private func sample(_ change: (inout [String: Any]) -> Void) throws -> Episode {
    var object = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(EpisodeCatalog.load("fish-plush"))) as? [String: Any])
    change(&object)
    return try JSONDecoder().decode(
      Episode.self, from: JSONSerialization.data(withJSONObject: object))
  }

  @Test func aBadEpisodeIsRefused() throws {
    #expect(throws: Episode.Problem.beats(4)) {
      try sample { $0["beats"] = Array(($0["beats"] as! [Any]).dropLast()) }.validate()
    }
    #expect(throws: Episode.Problem.unknownCulprit("cat")) {
      try sample { $0["culprit"] = "cat" }.validate()
    }
    #expect(throws: Episode.Problem.badID("Fish Plush")) {
      try sample { $0["id"] = "Fish Plush" }.validate()
    }
  }
}
