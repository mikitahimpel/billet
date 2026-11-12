import Foundation
import os

/// Intervals and events of a cold launch for Instruments and `log stream --predicate 'subsystem == "com.ourio.app"'`.
/// Each log line carries the milliseconds since the process started, which is the number a launch is judged by.
enum LaunchSignposts {
    private static let signposter = OSSignposter(subsystem: "com.ourio.app", category: "launch")
    private static let logger = Logger(subsystem: "com.ourio.app", category: "launch")

    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let began = Date.timeIntervalSinceReferenceDate
        defer {
            signposter.endInterval(name, state)
            let took = Int((Date.timeIntervalSinceReferenceDate - began) * 1000)
            logger.info("\(name, privacy: .public) took \(took, privacy: .public) ms, at \(sinceStart(), privacy: .public) ms")
        }
        return try body()
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
        logger.info("\(name, privacy: .public) at \(sinceStart(), privacy: .public) ms")
    }

    private static func sinceStart() -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return -1 }
        let started = info.kp_proc.p_un.__p_starttime
        let then = Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
        return Int((Date.now.timeIntervalSince1970 - then) * 1000)
    }
}
