import OSLog

/// Signposts for the room's load and its cost per frame, for Instruments.
enum NookiTrace {
  private static let signposter = OSSignposter(
    subsystem: "com.mikitahimpel.billet", category: "NookiScene")

  /// One moment of the load.
  static func mark(_ name: StaticString) {
    signposter.emitEvent(name)
  }

  /// The work the room does on the main thread in one frame.
  static func frame(_ body: () -> Void) {
    signposter.withIntervalSignpost("frame", around: body)
  }
}
