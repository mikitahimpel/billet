import os

/// Counts evaluations of one room's views, so a test or a perf run can tell that something outside made the room
/// re-render, or that the room's own ticks reached a view outside it.
final class RoomProbe: Sendable {
    private let counts = OSAllocatedUnfairLock(initialState: (host: 0, stage: 0))

    /// Evaluations of `RoomHost.body`: only a changed `RoomInput` should add to it.
    var hostBodies: Int { counts.withLock { $0.host } }
    /// Evaluations of the host's inner stage, which follows the controller's own state (a game, a new room).
    var stageBodies: Int { counts.withLock { $0.stage } }

    func hostBody() { counts.withLock { $0.host += 1 } }
    func stageBody() { counts.withLock { $0.stage += 1 } }
    func reset() { counts.withLock { $0 = (0, 0) } }
}
