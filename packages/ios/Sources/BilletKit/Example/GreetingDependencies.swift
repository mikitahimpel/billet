import OSLog

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

/// The composition root: the only place that names live services. Tests build
/// ``GreetingDependencies`` from fakes instead.
enum Live {
  static func greetingDependencies() -> GreetingDependencies {
    let logger = Logger(subsystem: "com.mikitahimpel.billet", category: "greeting")
    return GreetingDependencies(
      greetings: GreetingService { name throws(GreetingError) in
        guard !name.isEmpty else { throw .emptyName }
        return "Hello, \(name)"
      },
      activity: ActivityService { message in
        logger.info("\(message, privacy: .public)")
      }
    )
  }
}
