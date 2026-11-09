/// The worked example of the pattern: copy its shape when adding a feature machine.
enum GreetingMachine: Machine {
  /// `request` numbers each fetch, and a result whose ID is not the current one is stale.
  /// `idle` is request 0.
  enum State: Equatable, Sendable {
    case idle
    case loading(name: String, request: Int)
    case loaded(greeting: String, request: Int)
    case failed(name: String, error: GreetingError, request: Int)

    var request: Int {
      switch self {
      case .idle: 0
      case .loading(_, let request), .loaded(_, let request), .failed(_, _, let request): request
      }
    }
  }

  enum Event: Equatable, Sendable {
    case requested(name: String)
    case retried
    case greeted(String, request: Int)
    case rejected(GreetingError, request: Int)

    /// `nil` for an event that starts a request.
    var answeredRequest: Int? {
      switch self {
      case .requested, .retried: nil
      case .greeted(_, let request), .rejected(_, let request): request
      }
    }
  }

  enum Output: Equatable, Sendable {
    case fetchGreeting(name: String, request: Int)
    case record(String)
  }

  static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    // A late result for an earlier request, however it ends, must not touch the current one.
    if let answered = event.answeredRequest, answered != state.request {
      return (state, [])
    }

    let request = state.request + 1
    switch (state, event) {
    case (.idle, .requested(let name)),
      (.loaded, .requested(let name)),
      (.failed, .requested(let name)),
      (.failed(let name, _, _), .retried):
      return (
        .loading(name: name, request: request),
        [.fetchGreeting(name: name, request: request)]
      )

    case (.loading(_, let id), .greeted(let greeting, _)):
      return (.loaded(greeting: greeting, request: id), [.record("greeted")])

    case (.loading(let name, let id), .rejected(let error, _)):
      return (.failed(name: name, error: error, request: id), [.record("rejected")])

    case (.loading, .requested),
      (.idle, .retried),
      (.loading, .retried),
      (.loaded, .retried),
      (.idle, .greeted),
      (.loaded, .greeted),
      (.failed, .greeted),
      (.idle, .rejected),
      (.loaded, .rejected),
      (.failed, .rejected):
      return (state, [])
    }
  }

  /// The one place outputs reach services.
  static func run(_ output: Output, using dependencies: GreetingDependencies) async -> Event? {
    switch output {
    case .fetchGreeting(let name, let request):
      do {
        return .greeted(try await dependencies.greetings.fetch(name), request: request)
      } catch {
        return .rejected(error, request: request)
      }

    case .record(let message):
      await dependencies.activity.record(message)
      return nil
    }
  }
}
