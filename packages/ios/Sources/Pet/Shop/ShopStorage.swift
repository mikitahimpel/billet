import Foundation

/// Where the shop's state is kept between launches.
public struct ShopStorage: Sendable {
  public var load: @Sendable () -> ShopState?
  public var save: @Sendable (ShopState) -> Void

  public init(
    load: @escaping @Sendable () -> ShopState?, save: @escaping @Sendable (ShopState) -> Void
  ) {
    self.load = load
    self.save = save
  }

  /// One JSON value under `key`. A value that no longer decodes counts as no shop yet.
  public static func defaults(_ defaults: UserDefaults, key: String = "billet.shop") -> ShopStorage
  {
    nonisolated(unsafe) let defaults = defaults
    return ShopStorage(
      load: {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ShopState.self, from: $0) }
      },
      save: { state in
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
      })
  }

  public static func memory(_ initial: ShopState? = nil) -> ShopStorage {
    let box = MemoryBox(initial)
    return ShopStorage(load: { box.value }, save: { box.value = $0 })
  }

  private final class MemoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ShopState?

    init(_ value: ShopState?) { stored = value }

    var value: ShopState? {
      get { lock.withLock { stored } }
      set { lock.withLock { stored = newValue } }
    }
  }
}
