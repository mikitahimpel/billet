import Foundation
import OSLog

/// Signposts for the room's load and its cost per frame, for Instruments.
enum NookiTrace {
  private static let signposter = OSSignposter(
    subsystem: "com.mikitahimpel.billet", category: "NookiScene")
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiScene")

  /// One moment of the load. Also logged at debug level with the system uptime, so the time
  /// between two moments can be read from a log stream without Instruments.
  static func mark(_ name: StaticString) {
    signposter.emitEvent(name)
    let uptime = ProcessInfo.processInfo.systemUptime
    log.debug("mark \(String(describing: name), privacy: .public) at \(uptime, privacy: .public)")
  }

  /// The work the room does on the main thread in one frame.
  static func frame(_ body: () -> Void) {
    signposter.withIntervalSignpost("frame", around: body)
  }

  private static let motion = Logger(subsystem: "com.mikitahimpel.billet", category: "CatMotion")

  /// What the cat's body does each time it changes, at debug level, to find snaps in a log
  /// stream: a new clip, or a step or a turn bigger than a frame's walk or turn could be.
  static func catMotion(_ what: String, at clock: Double) {
    motion.debug("\(what, privacy: .public) at \(clock, privacy: .public)")
  }
}
