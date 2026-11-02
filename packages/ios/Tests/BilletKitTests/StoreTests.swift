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
  private let started = AsyncStream<Void>.makeStream()
  private let returned = AsyncStream<Void>.makeStream()

  var service: GreetingService {
    GreetingService { _ throws(GreetingError) in
      self.started.continuation.yield()
      defer { self.returned.continuation.yield() }
      var iterator = self.results.stream.makeAsyncIterator()
      guard let result = await iterator.next() else { throw .emptyName }
      return try result.get()
    }
  }

  /// Returns once a fetch has begun and is waiting to be resolved.
  func waitUntilFetching() async {
    var iterator = started.stream.makeAsyncIterator()
    _ = await iterator.next()
  }

  /// Returns once a fetch has returned its result to the store's task.
  func waitUntilFetchReturned() async {
    var iterator = returned.stream.makeAsyncIterator()
    _ = await iterator.next()
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

    #expect(store.state == .loaded(greeting: "Fake Ada", request: 1))
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
    #expect(store.state == .failed(name: "Ada", error: .emptyName, request: 1))

    store.send(.retried)
    gate.resolve(with: .success("Hi"))
    await store.settled()
    #expect(store.state == .loaded(greeting: "Hi", request: 2))
    #expect(activity.recorded == ["rejected", "greeted"])
  }

  @Test func stateChangesBeforeTheServiceReturns() async {
    let gate = GreetingGate()
    let store = makeStore(
      GreetingDependencies(greetings: gate.service, activity: ActivityRecorder().service)
    )

    store.send(.requested(name: "Ada"))
    #expect(store.state == .loading(name: "Ada", request: 1))

    gate.resolve(with: .success("Hi"))
    await store.settled()
    #expect(store.state == .loaded(greeting: "Hi", request: 1))
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

  @Test func runningOutputDoesNotRetainTheStore() async {
    let gate = GreetingGate()
    var store: Store<GreetingMachine>? = makeStore(
      GreetingDependencies(greetings: gate.service, activity: ActivityRecorder().service)
    )
    weak let released = store

    store?.send(.requested(name: "Ada"))
    // Let the output start, so what is released is a store with a call in flight.
    await gate.waitUntilFetching()
    store = nil

    #expect(released == nil)
    gate.resolve(with: .success("Hi"))
  }

  @Test func aResultThatArrivesAfterTheStoreIsGoneIsDropped() async {
    let gate = GreetingGate()
    let activity = ActivityRecorder()
    var store: Store<GreetingMachine>? = makeStore(
      GreetingDependencies(greetings: gate.service, activity: activity.service)
    )
    store?.send(.requested(name: "Ada"))
    await gate.waitUntilFetching()
    store = nil

    gate.resolve(with: .success("Hi"))
    await gate.waitUntilFetchReturned()
    // Let the store's task run the rest of its body. A late result that were fed back would
    // have recorded "greeted".
    for _ in 0..<50 { await Task.yield() }

    #expect(activity.recorded.isEmpty)
  }

  @Test func aStaleResultDoesNotOverwriteTheCurrentRequest() async {
    let gate = GreetingGate()
    let store = makeStore(
      GreetingDependencies(greetings: gate.service, activity: ActivityRecorder().service))

    store.send(.requested(name: "Ada"))
    gate.resolve(with: .failure(.emptyName))
    await store.settled()
    store.send(.requested(name: "Bo"))
    #expect(store.state == .loading(name: "Bo", request: 2))

    // The first request's answer arrives late, after the second was started.
    store.send(.greeted("Hi Ada", request: 1))
    #expect(store.state == .loading(name: "Bo", request: 2))

    gate.resolve(with: .success("Hi Bo"))
    await store.settled()
    #expect(store.state == .loaded(greeting: "Hi Bo", request: 2))
  }

  @Test func liveRootGreets() async {
    let store = makeStore(Live.greetingDependencies())

    store.send(.requested(name: "Ada"))
    await store.settled()

    #expect(store.state == .loaded(greeting: "Hello, Ada", request: 1))
  }

  @Test func liveRootRejectsAnEmptyName() async {
    let store = makeStore(Live.greetingDependencies())

    store.send(.requested(name: ""))
    await store.settled()

    #expect(store.state == .failed(name: "", error: .emptyName, request: 1))
  }
}
