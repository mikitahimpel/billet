import BilletKit
import Payments

/// What the store has on sale: nothing yet, the packs, or nothing because it couldn't be reached.
public nonisolated enum CoinShelfMachine: Machine {
  public enum State: Equatable, Sendable {
    case loading
    case ready([StampPack])
    case unavailable
  }

  public enum Event: Equatable, Sendable {
    case opened
    case loaded([StampPack])
    case loadFailed
  }

  public enum Output: Equatable, Sendable {
    case loadProducts
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.loading, .opened), (.unavailable, .opened): (.loading, [.loadProducts])
    case (.loading, .loaded(let packs)): (packs.isEmpty ? .unavailable : .ready(packs), [])
    case (.loading, .loadFailed): (.unavailable, [])
    case (.ready, .opened), (.ready, .loaded), (.ready, .loadFailed), (.unavailable, .loaded),
      (.unavailable, .loadFailed):
      (state, [])
    }
  }
}
