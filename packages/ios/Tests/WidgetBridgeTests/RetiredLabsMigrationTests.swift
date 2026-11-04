import Foundation
import Testing
import WidgetBridge

@Suite("Retired Labs migration")
struct RetiredLabsMigrationTests {
  private func freshDefaults() -> UserDefaults {
    let name = "retired-labs-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func forgetsTheFrameWallAndKeepsEverythingElse() {
    let defaults = freshDefaults()
    defaults.set(Data([1, 2]), forKey: "labs.framedNotes")
    defaults.set(Data([3]), forKey: "labs.framedNotes.fake")
    defaults.set(Data([4]), forKey: "labs.advent")
    RetiredLabsMigration.run(defaults: defaults)
    #expect(defaults.data(forKey: "labs.framedNotes") == nil)
    #expect(defaults.data(forKey: "labs.framedNotes.fake") == nil)
    #expect(defaults.data(forKey: "labs.advent") == Data([4]))
    RetiredLabsMigration.run(defaults: defaults)
    #expect(defaults.data(forKey: "labs.advent") == Data([4]))
  }

  @Test func aStoredSwitchOfARemovedExperimentIsDropped() throws {
    let json = Data(#"{"seasons":true,"twoWisps":false,"advent":false}"#.utf8)
    let features = try JSONDecoder().decode(WidgetFeatures.self, from: json)
    let saved = try JSONDecoder().decode(
      [String: Bool].self, from: JSONEncoder().encode(features))
    #expect(saved == ["advent": false])
    #expect(!features.isOn(.advent))
  }
}
