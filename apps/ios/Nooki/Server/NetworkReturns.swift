import Foundation
import Network

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
