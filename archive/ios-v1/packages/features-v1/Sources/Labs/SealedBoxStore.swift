import Foundation
import Observation
import Wire

/// The sealed box, kept in `defaults` so a note stays sealed across launches.
@MainActor
@Observable
public final class SealedBoxStore {
  public private(set) var box: SealedBox
  /// True when the next note drawn is to be sealed instead of sent.
  public var sealNext = false

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "labs.sealedBox") {
    self.defaults = defaults
    self.key = key
    box =
      defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SealedBox.self, from: $0) }
      ?? SealedBox()
  }

  public func seal(_ note: SealedNote) {
    box.seal(note)
    save()
  }

  /// The notes whose time has come. They leave the box.
  public func release(at now: Date) -> [SealedNote] {
    let due = box.release(at: now)
    if !due.isEmpty { save() }
    return due
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(box), forKey: key)
  }
}
