/// The worked example of the pattern: copy its shape when adding a feature machine.
///
/// Each state carries only the data valid in it, so a failed greeting cannot also hold a result.
/// Results carry the number of the request they answer, so a late one is told from the current one.
enum GreetingMachine: Machine {
  /// `request` numbers each fetch. It is how a result is matched to the request that asked for it:
  /// ``Store`` does not correlate them, so a machine whose outputs can overlap carries an ID in its
  /// state, puts it in the output, and has the result bring it back. A result whose ID is not the
  /// current one is stale and changes nothing. `idle` is request 0; each new request is the last
  /// one plus one.
  enum State: Equatable, Sendable {
    case idle
    case loading(name: String, request: Int)
    case loaded(greeting: String, request: Int)
    case failed(name: String, error: GreetingError, request: Int)

    /// The latest request this state knows of.
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

    /// The request a result answers, or `nil` for an event that starts one.
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

  /// The interpreter handed to a ``Store``: the one place outputs reach services.
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
