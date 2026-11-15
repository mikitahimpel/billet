import Foundation
import Transport

/// Tries a send again while it reports something still waiting on the network, 2 s after the first failure and twice
/// as long after each next one, up to `ceiling`. Ends when nothing waits or the task is cancelled.
public struct Resend: Sendable {
  var first: Duration
  var ceiling: Duration
  var sleep: @Sendable (Duration) async throws -> Void

  public init(
    first: Duration = .seconds(2), ceiling: Duration = .seconds(300),
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.first = first
    self.ceiling = ceiling
    self.sleep = sleep
  }

  public func delay(after failures: Int) -> Duration {
    var delay = first
    for _ in 1..<max(failures, 1) where delay < ceiling { delay = delay * 2 }
    return min(delay, ceiling)
  }

  /// `attempt` returns true while something is still waiting.
  public func run(_ attempt: () async -> Bool) async {
    var failures = 0
    while !Task.isCancelled, await attempt() {
      failures += 1
      do { try await sleep(delay(after: failures)) } catch { return }
    }
  }
}

nonisolated extension TransportError {
  /// The server didn't take it but may later: out of reach, down, or the session not ready yet. Anything else is
  /// its answer, and sending the same request again gets the same one.
  public var isWorthRetrying: Bool {
    switch self {
    case .network, .maintenance: true
    case .status(let code): code >= 500 || code == 429 || code == 408
    case .api(let error): error == .unauthorized || error == .unavailable
    case .encoding, .decoding: false
    }
  }
}
