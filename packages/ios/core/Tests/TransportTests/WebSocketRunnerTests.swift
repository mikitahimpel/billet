import Testing
import Wire

@testable import Transport

@Suite struct WebSocketRunnerTests {
  static func dependencies(
    pool: ConnectionPool,
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      // Connect timeouts and the stability timer never fire unless a test asks for one.
      if duration == WebSocketMachine.connectTimeout || duration == WebSocketMachine.stableAfter {
        try? await Task.sleep(for: .seconds(3600))
      }
    },
    deliver: @escaping @Sendable (ServerMessage) async -> Void = { _ in },
    open: (@Sendable () async throws(TransportError) -> WebSocketConnection)? = nil
  ) -> WebSocketDependencies {
    // `if let`, not `??`: the Xcode 27.1 compiler crashes emitting a typed-throws closure wrapped
    // in the autoclosure `??` makes.
    let opener: @Sendable () async throws(TransportError) -> WebSocketConnection
    if let open {
      opener = open
    } else {
      opener = { () async throws(TransportError) -> WebSocketConnection in
        guard let connection = await pool.next() else { throw .network("no connection") }
        return connection
      }
    }
    return WebSocketDependencies(
      open: opener,
      sleep: sleep,
      deliver: deliver,
      jitter: { 1 }
    )
  }

  @Test func openReportsOpenedThenMessagesThenDrop() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    #expect(await runner.run(.open(attempt: 1, resumeFrom: 0)) == nil)
    socket.incoming.yield(.presence(.drawing))
    socket.incoming.finish()

    var events: [WebSocketMachine.Event] = []
    for await event in runner.events {
      events.append(event)
      if events.count == 3 { break }
    }
    #expect(
      events == [
        .opened(attempt: 1), .received(attempt: 1, .presence(.drawing)), .dropped(attempt: 1),
      ])
  }

  @Test func failedOpenIsADrop() async {
    let runner = WebSocketRunner(dependencies: Self.dependencies(pool: ConnectionPool([])))
    #expect(await runner.run(.open(attempt: 4, resumeFrom: 0)) == .dropped(attempt: 4))
  }

  @Test func closeEndsTheAttemptsSocket() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 1, resumeFrom: 0))
    _ = await runner.run(.close(attempt: 1))
    // Closing finished the fake's incoming stream, so reading it ends at once.
    var remaining = 0
    for await _ in socket.connection.messages { remaining += 1 }
    #expect(remaining == 0)
    // With the socket released, a send to that attempt does nothing.
    #expect(await runner.run(.send(.presence(.idle), attempt: 1)) == nil)
  }

  @Test func closeOfAnotherAttemptLeavesTheSocketOpen() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 2, resumeFrom: 0))
    _ = await runner.run(.close(attempt: 1))
    _ = await runner.run(.send(.presence(.drawing), attempt: 2))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 0))
    #expect(await iterator.next() == .presence(.drawing))
  }

  @Test func aSocketThatFollowsActivityAsksForItInEachResume() async {
    let socket = makeFakeSocket()
    var dependencies = Self.dependencies(pool: ConnectionPool([socket.connection]))
    dependencies.followsActivity = true
    let runner = WebSocketRunner(dependencies: dependencies)

    _ = await runner.run(.open(attempt: 1, resumeFrom: 3))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 3, activity: true))
  }

  @Test func aSocketThatFollowsTheShopAsksForItInEachResume() async {
    let socket = makeFakeSocket()
    var dependencies = Self.dependencies(pool: ConnectionPool([socket.connection]))
    dependencies.followsShop = true
    let runner = WebSocketRunner(dependencies: dependencies)

    _ = await runner.run(.open(attempt: 1, resumeFrom: 3))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 3, shop: true))
  }

  @Test func aSocketThatFollowsTheListsAsksForThemInEachResume() async {
    let socket = makeFakeSocket()
    var dependencies = Self.dependencies(pool: ConnectionPool([socket.connection]))
    dependencies.followsLists = true
    let runner = WebSocketRunner(dependencies: dependencies)

    _ = await runner.run(.open(attempt: 1, resumeFrom: 3))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 3, lists: true))
  }

  @Test func openingSendsTheResumeFirst() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 1, resumeFrom: 7))
    // A send right after the open, as the caller makes once `opened` arrives, still goes after it.
    runner.enqueue(.presence(.drawing), attempt: 1)

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 7))
    #expect(await iterator.next() == .presence(.drawing))
  }

  @Test func sendGoesToTheOpenSocket() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 1, resumeFrom: 0))
    #expect(await runner.run(.send(.presence(.idle), attempt: 1)) == nil)

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 0))
    #expect(await iterator.next() == .presence(.idle))
  }

  @Test func queuedSendsKeepTheirOrder() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 1, resumeFrom: 0))
    let frames = (0..<200).map { ClientMessage.strokeEnd(id: $0) }
    for frame in frames { runner.enqueue(frame, attempt: 1) }

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 0))
    var received: [ClientMessage] = []
    while received.count < frames.count, let next = await iterator.next() { received.append(next) }
    #expect(received == frames)
  }

  @Test func aFailedSendReportsTheDrop() async {
    let incoming = AsyncStream.makeStream(of: ServerMessage.self)
    let failing = WebSocketConnection(
      messages: incoming.stream,
      send: { (_) async throws(TransportError) in throw .network("gone") },
      close: { incoming.continuation.finish() })
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([failing])))

    _ = await runner.run(.open(attempt: 1, resumeFrom: 0))

    // The Resume queued on opening fails, and its drop may be reported before `opened` is.
    var events = runner.events.makeAsyncIterator()
    var first: [WebSocketMachine.Event] = []
    while first.count < 2, let event = await events.next() { first.append(event) }
    #expect(Set(first.map { "\($0)" }) == ["opened(attempt: 1)", "dropped(attempt: 1)"])
  }

  @Test func sendWithoutASocketDoesNothing() async {
    let runner = WebSocketRunner(dependencies: Self.dependencies(pool: ConnectionPool([])))
    #expect(await runner.run(.send(.presence(.idle), attempt: 1)) == nil)
  }

  @Test func retrySleepsForTheBackoffThenElapses() async {
    let delays = AsyncStream.makeStream(of: Duration.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([]),
        sleep: { duration in _ = delays.continuation.yield(duration) }))

    let event = await runner.run(.scheduleRetry(afterFailures: 3, attempt: 5))
    #expect(event == .retryElapsed(attempt: 5))
    var iterator = delays.stream.makeAsyncIterator()
    #expect(await iterator.next() == .seconds(4))
  }

  @Test func connectTimeoutSleepsThenReportsTheAttempt() async {
    let delays = AsyncStream.makeStream(of: Duration.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([]),
        sleep: { duration in _ = delays.continuation.yield(duration) }))

    let event = await runner.run(.startConnectTimeout(attempt: 2))
    #expect(event == .connectTimedOut(attempt: 2))
    var iterator = delays.stream.makeAsyncIterator()
    #expect(await iterator.next() == WebSocketMachine.connectTimeout)
  }

  @Test func deliverHandsTheMessageToTheDependency() async {
    let delivered = AsyncStream.makeStream(of: ServerMessage.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([]),
        deliver: { message in _ = delivered.continuation.yield(message) }))

    #expect(await runner.run(.deliver(.presence(.drawing))) == nil)
    var iterator = delivered.stream.makeAsyncIterator()
    #expect(await iterator.next() == .presence(.drawing))
  }

  @Test func closeCancelsAConnectThatIsStillOpening() async {
    let cancelled = AsyncStream.makeStream(of: Bool.self)
    let started = AsyncStream.makeStream(of: Void.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([]),
        open: { () async throws(TransportError) -> WebSocketConnection in
          started.continuation.yield()
          // A handshake that never answers, and only ends when it is cancelled.
          try? await Task.sleep(for: .seconds(3600))
          cancelled.continuation.yield(Task.isCancelled)
          throw .network("cancelled")
        }))

    let opening = Task { await runner.run(.open(attempt: 1, resumeFrom: 0)) }
    var startedIterator = started.stream.makeAsyncIterator()
    await startedIterator.next()
    _ = await runner.run(.close(attempt: 1))

    var iterator = cancelled.stream.makeAsyncIterator()
    #expect(await iterator.next() == true)
    #expect(await opening.value == .dropped(attempt: 1))
  }

  @Test func closeStopsTheConnectTimeoutInsteadOfLettingItFire() async {
    let started = AsyncStream.makeStream(of: Void.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([]),
        sleep: { _ in
          started.continuation.yield()
          try? await Task.sleep(for: .seconds(3600))
        }))

    let timer = Task { await runner.run(.startConnectTimeout(attempt: 3)) }
    var iterator = started.stream.makeAsyncIterator()
    await iterator.next()
    _ = await runner.run(.close(attempt: 3))
    #expect(await timer.value == nil)
  }

  @Test func openingCancelsTheConnectTimeout() async {
    let socket = makeFakeSocket()
    let started = AsyncStream.makeStream(of: Void.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([socket.connection]),
        sleep: { _ in
          started.continuation.yield()
          try? await Task.sleep(for: .seconds(3600))
        }))

    let timer = Task { await runner.run(.startConnectTimeout(attempt: 1)) }
    var iterator = started.stream.makeAsyncIterator()
    await iterator.next()
    _ = await runner.run(.open(attempt: 1, resumeFrom: 0))
    #expect(await timer.value == nil)
  }

  @Test func stabilityTimerReportsTheAttemptAfterTheStablePeriod() async {
    let delays = AsyncStream.makeStream(of: Duration.self)
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(
        pool: ConnectionPool([]),
        sleep: { duration in _ = delays.continuation.yield(duration) }))

    #expect(await runner.run(.startStabilityTimer(attempt: 6)) == .stable(attempt: 6))
    var iterator = delays.stream.makeAsyncIterator()
    #expect(await iterator.next() == WebSocketMachine.stableAfter)
  }

  @Test func retryDelayIsMultipliedByTheJitter() async {
    let delays = AsyncStream.makeStream(of: Duration.self)
    let dependencies = WebSocketDependencies(
      open: { () async throws(TransportError) -> WebSocketConnection in throw .network("none") },
      sleep: { duration in _ = delays.continuation.yield(duration) },
      deliver: { _ in },
      jitter: { 1.5 })
    let runner = WebSocketRunner(dependencies: dependencies)

    _ = await runner.run(.scheduleRetry(afterFailures: 3, attempt: 1))
    var iterator = delays.stream.makeAsyncIterator()
    #expect(await iterator.next() == .seconds(6))
  }

  @Test func shutdownClosesEverySocketAndEndsTheEvents() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))
    _ = await runner.run(.open(attempt: 1, resumeFrom: 0))
    await runner.shutdown()

    var remaining = 0
    for await _ in socket.connection.messages { remaining += 1 }
    #expect(remaining == 0)
    var events = 0
    for await _ in runner.events { events += 1 }
    #expect(events >= 1)
  }
}
