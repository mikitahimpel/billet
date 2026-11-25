import Foundation
import Persistence

/// The one card that tells a new pair about Plus. It shows once, after onboarding, to a pair that
/// is together and has nothing from the partner waiting, and only while Plus is on offer to them.
/// Once it has been on screen it never comes back, dismissed or not.
public nonisolated struct PlusWelcome: Codable, Equatable, Sendable {
  public var shownAt: Date?

  public init(shownAt: Date? = nil) {
    self.shownAt = shownAt
  }

  public func shows(onboarded: Bool, paired: Bool, partnerWaiting: Bool, entry: PlusEntry) -> Bool {
    guard shownAt == nil, onboarded, paired, !partnerWaiting else { return false }
    switch entry {
    case .offer: return true
    case .hidden, .parcels, .has: return false
    }
  }
}

/// Keeps ``PlusWelcome`` in the App Group. A file that can't be read counts as shown: at worst
/// the card is never offered.
public nonisolated struct PlusWelcomeStore: Sendable {
  public var load: @Sendable () -> PlusWelcome
  public var save: @Sendable (PlusWelcome) -> Void

  public init(
    load: @escaping @Sendable () -> PlusWelcome, save: @escaping @Sendable (PlusWelcome) -> Void
  ) {
    self.load = load
    self.save = save
  }

  public static func storage(_ storage: AppGroupStorage, now: @escaping @Sendable () -> Date)
    -> PlusWelcomeStore
  {
    let name = "plus-welcome.json"
    return PlusWelcomeStore(
      load: {
        do throws(PersistenceError) {
          return try storage.readJSON(PlusWelcome.self, named: name) ?? PlusWelcome()
        } catch {
          return PlusWelcome(shownAt: now())
        }
      },
      save: { welcome in try? storage.writeJSON(welcome, named: name) })
  }
}
