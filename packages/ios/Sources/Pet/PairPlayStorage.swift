import Foundation

/// Where a pair's play is kept when no room holds it.
public struct PairPlayStorage: Sendable {
  public var load: @Sendable () -> PairPlay.Saved?
  public var save: @Sendable (PairPlay.Saved) -> Void

  public init(
    load: @escaping @Sendable () -> PairPlay.Saved?,
    save: @escaping @Sendable (PairPlay.Saved) -> Void
  ) {
    self.load = load
    self.save = save
  }

  /// One JSON value under `key`. A value that no longer decodes counts as nothing saved.
  public static func defaults(_ defaults: UserDefaults, key: String) -> PairPlayStorage {
    nonisolated(unsafe) let defaults = defaults
    return PairPlayStorage(
      load: {
        defaults.data(forKey: key).flatMap {
          try? JSONDecoder().decode(PairPlay.Saved.self, from: $0)
        }
      },
      save: { saved in
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
      })
  }
}
