import Foundation
import Synchronization

@testable import Persistence

/// An in-memory Keychain that records what it was asked.
final class FakeKeychain: Sendable {
  struct State: Sendable {
    var items: [KeychainItemKey: Data] = [:]
    var adds: [KeychainItemKey] = []
    var updates = 0
    var failWith: Int32?
  }

  private let state = Mutex(State())

  var snapshot: State { state.withLock { $0 } }

  func failEveryCall(with status: Int32) {
    state.withLock { $0.failWith = status }
  }

  var client: KeychainClient {
    KeychainClient(
      add: { key, data in
        self.state.withLock { state in
          if let status = state.failWith { return status }
          state.adds.append(key)
          if state.items[key] != nil { return KeychainStatus.duplicateItem }
          state.items[key] = data
          return KeychainStatus.success
        }
      },
      update: { key, data in
        self.state.withLock { state in
          if let status = state.failWith { return status }
          state.updates += 1
          guard state.items[key] != nil else { return KeychainStatus.itemNotFound }
          state.items[key] = data
          return KeychainStatus.success
        }
      },
      read: { key in
        self.state.withLock { state in
          if let status = state.failWith { return KeychainReadResult(status: status, data: nil) }
          guard let data = state.items[key] else {
            return KeychainReadResult(status: KeychainStatus.itemNotFound, data: nil)
          }
          return KeychainReadResult(status: KeychainStatus.success, data: data)
        }
      },
      delete: { key in
        self.state.withLock { state in
          if let status = state.failWith { return status }
          return state.items.removeValue(forKey: key) == nil
            ? KeychainStatus.itemNotFound : KeychainStatus.success
        }
      }
    )
  }
}
