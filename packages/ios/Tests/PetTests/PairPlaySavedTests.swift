import Foundation
import Testing

@testable import Pet

@Suite struct PairPlaySavedTests {
  private let suite = "pair-play-\(UUID().uuidString)"
  private var storage: PairPlayStorage {
    .defaults(UserDefaults(suiteName: suite) ?? .standard, key: "play")
  }

  @Test func playSurvivesASaveAndLoad() {
    var play = PairPlay(device: "me")
    play.named("Mochi")
    _ = play.treatGiven(on: "2026-11-02")
    let note = UUID()
    play.reactionGiven(to: note, .heart)
    storage.save(play.saved)
    let loaded = PairPlay(device: "me", saved: storage.load())
    #expect(loaded.saved == play.saved)
  }

  @Test func nothingSavedLoadsAsNothing() {
    #expect(storage.load() == nil)
  }
}
