import Foundation

public struct MockSwitches: Sendable {
  public enum Outcome: String, CaseIterable, Hashable, Sendable {
    case succeed
    case cancel
    case fail
    /// Waits until approved or declined in Labs.
    case pending

    public var title: String {
      switch self {
      case .succeed: "Succeed"
      case .cancel: "Cancel"
      case .fail: "Fail"
      case .pending: "Ask to Buy"
      }
    }
  }

  public static let outcomeKey = "labs.payments.mock.outcome"

  private let read: @Sendable () -> Outcome
  private let write: @Sendable (Outcome) -> Void

  public init(
    read: @escaping @Sendable () -> Outcome, write: @escaping @Sendable (Outcome) -> Void
  ) {
    self.read = read
    self.write = write
  }

  public var outcome: Outcome {
    get { read() }
    nonmutating set { write(newValue) }
  }

  /// Switches kept in `defaults` under ``outcomeKey``.
  public static func defaults(_ defaults: UserDefaults) -> MockSwitches {
    nonisolated(unsafe) let defaults = defaults
    return MockSwitches(
      read: { defaults.string(forKey: outcomeKey).flatMap(Outcome.init(rawValue:)) ?? .succeed },
      write: { defaults.set($0.rawValue, forKey: outcomeKey) })
  }

  public static func fixed(_ outcome: Outcome) -> MockSwitches {
    MockSwitches(read: { outcome }, write: { _ in })
  }
}
