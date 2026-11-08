import os

/// Counts evaluations of the room's views, so a test or a perf run can tell that something outside made the
/// room re-render, or that the room's own ticks reached a view outside it.
enum RoomProbe {
    private static let counts = OSAllocatedUnfairLock(initialState: (host: 0, stage: 0))

    /// Evaluations of `RoomHost.body`: only a changed `RoomInput` should add to it.
    static var hostBodies: Int { counts.withLock { $0.host } }
    /// Evaluations of the host's inner stage, which follows the controller's own state (a pulse, a game, a new room).
    static var stageBodies: Int { counts.withLock { $0.stage } }

    static func hostBody() { counts.withLock { $0.host += 1 } }
    static func stageBody() { counts.withLock { $0.stage += 1 } }
    static func reset() { counts.withLock { $0 = (0, 0) } }
}
