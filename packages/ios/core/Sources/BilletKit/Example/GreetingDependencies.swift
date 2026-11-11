#if canImport(OSLog)
  import OSLog
#endif

enum GreetingError: Error, Equatable, Sendable {
  case emptyName
}

struct GreetingService: Sendable {
  var fetch: @Sendable (_ name: String) async throws(GreetingError) -> String
}

struct ActivityService: Sendable {
  var record: @Sendable (_ message: String) async -> Void
}

struct GreetingDependencies: Sendable {
  var greetings: GreetingService
  var activity: ActivityService
}

/// The only place that names live services.
enum Live {
  static func greetingDependencies() -> GreetingDependencies {
    #if canImport(OSLog)
      let logger = Logger(subsystem: "com.ourio.app", category: "greeting")
    #endif
    return GreetingDependencies(
      greetings: GreetingService { name throws(GreetingError) in
        guard !name.isEmpty else { throw .emptyName }
        return "Hello, \(name)"
      },
      activity: ActivityService { message in
        #if canImport(OSLog)
          logger.info("\(message, privacy: .public)")
        #endif
      }
    )
  }
}
