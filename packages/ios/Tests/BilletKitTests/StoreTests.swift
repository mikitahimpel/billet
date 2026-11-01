import Observation
import Synchronization
import Testing

@testable import BilletKit

private final class ActivityRecorder: Sendable {
  private let messages = Mutex<[String]>([])

  var recorded: [String] { messages.withLock { $0 } }

  var service: ActivityService {
    ActivityService { message in self.messages.withLock { $0.append(message) } }
  }
}

/// Suspends each fetch until the test resolves it, so a test can look at the in-flight state.
private final class GreetingGate: Sendable {
  private let results = AsyncStream<Result<String, GreetingError>>.makeStream()

  var service: GreetingService {
    GreetingService { _ throws(GreetingError) in
      var iterator = self.results.stream.makeAsyncIterator()
      guard let result = await iterator.next() else { throw .emptyName }
      return try result.get()
    }
  }

  func resolve(with result: Result<String, GreetingError>) {
    results.continuation.yield(result)
  }
}

@MainActor
private func makeStore(_ dependencies: GreetingDependencies) -> Store<GreetingMachine> {
  Store(initial: .idle) { await GreetingMachine.run($0, using: dependencies) }
}

@MainActor
@Suite struct StoreTests {
  @Test func fakeServiceResultIsFedBackAsAnEvent() async {
    let activity = ActivityRecorder()
    let store = makeStore(
      GreetingDependencies(
        greetings: GreetingService { name throws(GreetingError) in "Fake \(name)" },
        activity: activity.service
      )
    )

    store.send(.requested(name: "Ada"))
    await store.settled()

    #expect(store.state == .loaded(greeting: "Fake Ada"))
    #expect(activity.recorded == ["greeted"])
  }

  @Test func typedFailureBecomesAnEventAndRetryRecovers() async {
    let gate = GreetingGate()
    let activity = ActivityRecorder()
    let store = makeStore(
      GreetingDependencies(greetings: gate.service, activity: activity.service)
    )

    store.send(.requested(name: "Ada"))
    gate.resolve(with: .failure(.emptyName))
    await store.settled()
    #expect(store.state == .failed(name: "Ada", error: .emptyName))

    store.send(.retried)
    gate.resolve(with: .success("Hi"))
    await store.settled()
    #expect(store.state == .loaded(greeting: "Hi"))
    #expect(activity.recorded == ["rejected", "greeted"])
  }

  @Test func stateChangesBeforeTheServiceReturns() async {
    let gate = GreetingGate()
    let store = makeStore(
      GreetingDependencies(greetings: gate.service, activity: ActivityRecorder().service)
    )

    store.send(.requested(name: "Ada"))
    #expect(store.state == .loading(name: "Ada"))

    gate.resolve(with: .success("Hi"))
    await store.settled()
    #expect(store.state == .loaded(greeting: "Hi"))
  }

  @Test func observersSeeStateChanges() async {
    let store = makeStore(Live.greetingDependencies())
    let changed = Mutex(false)

    withObservationTracking {
      _ = store.state
    } onChange: {
      changed.withLock { $0 = true }
    }
    store.send(.requested(name: "Ada"))
    await store.settled()

    #expect(changed.withLock { $0 })
  }

  @Test func runningOutputDoesNotRetainTheStore() {
    let gate = GreetingGate()
    var store: Store<GreetingMachine>? = makeStore(
      GreetingDependencies(greetings: gate.service, activity: ActivityRecorder().service)
    )
    weak let released = store

    store?.send(.requested(name: "Ada"))
    store = nil

    #expect(released == nil)
    gate.resolve(with: .success("Hi"))
  }

  @Test func liveRootGreets() async {
    let store = makeStore(Live.greetingDependencies())

    store.send(.requested(name: "Ada"))
    await store.settled()

    #expect(store.state == .loaded(greeting: "Hello, Ada"))
  }

  @Test func liveRootRejectsAnEmptyName() async {
    let store = makeStore(Live.greetingDependencies())

    store.send(.requested(name: ""))
    await store.settled()

    #expect(store.state == .failed(name: "", error: .emptyName))
  }
}
