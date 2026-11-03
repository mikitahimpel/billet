import Foundation
import Persistence
import Pet
import Testing

@testable import WidgetBridge

@Suite @MainActor struct CatTemperamentStoreTests {
  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func aCatFromBeforeTemperamentsGetsTheOneThatFitsItOnce() {
    let store = WidgetFeaturesStore(storage: storage())
    #expect(store.loadTemperament() == nil)
    let seed = StableHash.of("pair-1/detailed/natural")
    let model = WidgetFeaturesModel(store: store)
    #expect(model.temperamentRecord == nil)
    let temperament = model.temperament(forSeed: seed)
    #expect(temperament == CatTemperament.born(seed: seed))
    #expect(store.loadTemperament() == CatTemperamentRecord(seed: seed, temperament: temperament))
    #expect(WidgetFeaturesModel(store: store).temperament(forSeed: seed) == temperament)
  }

  @Test func aSavedTemperamentIsKeptForLife() throws {
    let store = WidgetFeaturesStore(storage: storage())
    let seed = StableHash.of("pair-2/detailed/natural")
    let other = try #require(CatTemperament.allCases.first { $0 != .born(seed: seed) })
    try store.saveTemperament(CatTemperamentRecord(seed: seed, temperament: other))
    #expect(WidgetFeaturesModel(store: store).temperament(forSeed: seed) == other)
  }

  @Test func aNewCatIsBornWithItsOwn() {
    let store = WidgetFeaturesStore(storage: storage())
    let model = WidgetFeaturesModel(store: store)
    _ = model.temperament(forSeed: 1)
    let seed = StableHash.of("pair-3/detailed/natural")
    #expect(model.temperament(forSeed: seed) == CatTemperament.born(seed: seed))
    #expect(store.loadTemperament()?.seed == seed)
  }

  @Test func everySeedSurvivesTheFile() throws {
    let store = WidgetFeaturesStore(storage: storage())
    for seed in [UInt64.max, 1 << 60 + 1, 0] {
      try store.saveTemperament(CatTemperamentRecord(seed: seed, temperament: .clown))
      #expect(store.loadTemperament()?.seed == seed)
    }
  }

  @Test func aBrokenFileIsBornAgain() throws {
    let storage = storage()
    try storage.write(WidgetFeaturesStore.temperamentFileName, Data("not json".utf8))
    let store = WidgetFeaturesStore(storage: storage)
    #expect(store.loadTemperament() == nil)
    #expect(WidgetFeaturesModel(store: store).temperament(forSeed: 9) == .born(seed: 9))
  }
}
