import Foundation
import Network

/// Tries a send again while it reports something still waiting on the network, 2 s after the first failure and twice
/// as long after each next one, up to `ceiling`. Ends when nothing waits or the task is cancelled.
struct Resend: Sendable {
    var first: Duration = .seconds(2)
    var ceiling: Duration = .seconds(300)
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func delay(after failures: Int) -> Duration {
        var delay = first
        for _ in 1..<max(failures, 1) where delay < ceiling { delay = delay * 2 }
        return min(delay, ceiling)
    }

    /// `attempt` returns true while something is still waiting.
    func run(_ attempt: () async -> Bool) async {
        var failures = 0
        while !Task.isCancelled, await attempt() {
            failures += 1
            do { try await sleep(delay(after: failures)) } catch { return }
        }
    }
}

/// Yields each time the phone gets a usable network path back after losing it. Off the main actor: the monitor calls
/// back on its own queue.
nonisolated enum NetworkReturns {
    static func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let online = OnlineFlag()
            monitor.pathUpdateHandler = { path in
                if online.update(path.status == .satisfied) { continuation.yield() }
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "billet.network-returns"))
        }
    }
}

/// Touched only on the monitor's serial queue.
nonisolated private final class OnlineFlag: @unchecked Sendable {
    private var online: Bool?

    /// True when `now` is online and the last path seen was not.
    func update(_ now: Bool) -> Bool {
        defer { online = now }
        return now && online == false
    }
}
