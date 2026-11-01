/// The worked example of the pattern: copy its shape when adding a feature machine.
///
/// Each state carries only the data valid in it, so a failed greeting cannot also hold a result.
enum GreetingMachine: Machine {
  enum State: Equatable, Sendable {
    case idle
    case loading(name: String)
    case loaded(greeting: String)
    case failed(name: String, error: GreetingError)
  }

  enum Event: Equatable, Sendable {
    case requested(name: String)
    case retried
    case greeted(String)
    case rejected(GreetingError)
  }

  enum Output: Equatable, Sendable {
    case fetchGreeting(name: String)
    case record(String)
  }

  static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.idle, .requested(let name)),
      (.loaded, .requested(let name)),
      (.failed, .requested(let name)),
      (.failed(let name, _), .retried):
      return (.loading(name: name), [.fetchGreeting(name: name)])

    case (.loading, .greeted(let greeting)):
      return (.loaded(greeting: greeting), [.record("greeted")])

    case (.loading(let name), .rejected(let error)):
      return (.failed(name: name, error: error), [.record("rejected")])

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
    case .fetchGreeting(let name):
      do {
        return .greeted(try await dependencies.greetings.fetch(name))
      } catch {
        return .rejected(error)
      }

    case .record(let message):
      await dependencies.activity.record(message)
      return nil
    }
  }
}
