import BilletKit
import DecorInterface
import Foundation
import Persistence

public typealias DecorStore = Store<DecorMachine>

/// Where the arrangement is kept: one file in the App Group.
public struct DecorStorage: Sendable {
  public var load: @Sendable () -> DecorLayout?
  public var save: @Sendable (DecorLayout) -> Void

  public init(
    load: @escaping @Sendable () -> DecorLayout?, save: @escaping @Sendable (DecorLayout) -> Void
  ) {
    self.load = load
    self.save = save
  }

  public static let fileName = "decor-layout.json"

  public static func appGroup(_ storage: AppGroupStorage) -> DecorStorage {
    DecorStorage(
      load: {
        guard let data = try? storage.read(fileName) else { return nil }
        return try? JSONDecoder().decode(DecorLayout.self, from: data)
      },
      save: { layout in
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? storage.write(fileName, data)
      })
  }
}

/// What the store's outputs run on.
public struct DecorServices: Sendable {
  public var storage: DecorStorage
  /// A tap of the haptic motor and the like; the app decides what each feedback is.
  public var feedback: @MainActor @Sendable (DecorMachine.Feedback) -> Void
  /// A change the player made, for the server.
  public var share: @MainActor @Sendable (DecorLayout) -> Void

  public init(
    storage: DecorStorage, feedback: @escaping @MainActor @Sendable (DecorMachine.Feedback) -> Void,
    share: @escaping @MainActor @Sendable (DecorLayout) -> Void = { _ in }
  ) {
    self.storage = storage
    self.feedback = feedback
    self.share = share
  }
}

extension Store where M == DecorMachine {
  /// The store at the arrangement last kept, with nothing owned until `.owned` says so.
  @MainActor
  public static func decor(_ services: DecorServices) -> DecorStore {
    let layout = services.storage.load() ?? DecorLayout()
    return DecorStore(initial: .off(DecorMachine.Book(layout: layout))) { output in
      switch output {
      case .save(let layout):
        services.storage.save(layout)
        await services.share(layout)
      case .keep(let layout): services.storage.save(layout)
      case .feedback(let kind): await services.feedback(kind)
      }
      return nil
    }
  }
}

extension DecorMachine.State {
  public var closetCount: Int { book.closet.count }
  public var placedCount: Int { book.layout.placedCount(owned: book.owned) }
}
