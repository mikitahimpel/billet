import BilletKit

/// The item sheet from the first look to the end: a buy keeps it open on Place now; short of coins it gives way to
/// the Coins sheet.
nonisolated enum ItemSheetMachine: Machine {
  enum State: Equatable, Sendable {
    case previewing
    case bought
    case closed
  }

  enum Event: Equatable, Sendable {
    case bought
    case placeNowTapped
    case notNowTapped
    case coinsAsked
  }

  enum Output: Equatable, Sendable {
    case openRoom
    case close
  }

  static func initial(owned: Bool) -> State { owned ? .bought : .previewing }

  static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.previewing, .bought): (.bought, [])
    case (.previewing, .coinsAsked): (.closed, [.close])
    case (.bought, .placeNowTapped): (.closed, [.openRoom, .close])
    case (.bought, .notNowTapped): (.closed, [.close])
    case (.previewing, .placeNowTapped), (.previewing, .notNowTapped),
      (.bought, .bought), (.bought, .coinsAsked),
      (.closed, .bought), (.closed, .placeNowTapped), (.closed, .notNowTapped),
      (.closed, .coinsAsked):
      (state, [])
    }
  }
}
