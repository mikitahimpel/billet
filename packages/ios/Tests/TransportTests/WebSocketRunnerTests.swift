import Testing
import Wire

@testable import Transport

@Suite struct WebSocketRunnerTests {
  static func dependencies(
    pool: ConnectionPool,
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      // Connect timeouts never fire unless a test asks for one.
      if duration == WebSocketMachine.connectTimeout {
        try? await Task.sleep(for: .seconds(3600))
      }
    },
    deliver: @escaping @Sendable (ServerMessage) async -> Void = { _ in }
  ) -> WebSocketDependencies {
    WebSocketDependencies(
      open: { () async throws(TransportError) -> WebSocketConnection in
        guard let connection = await pool.next() else { throw .network("no connection") }
        return connection
      },
      sleep: sleep,
      deliver: deliver
    )
  }

  @Test func openReportsOpenedThenMessagesThenDrop() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    #expect(await runner.run(.open(attempt: 1)) == nil)
    socket.incoming.yield(.presence(.drawing))
    socket.incoming.finish()

    var events: [WebSocketMachine.Event] = []
    for await event in runner.events {
      events.append(event)
      if events.count == 3 { break }
    }
    #expect(events == [
        .opened(attempt: 1), .received(attempt: 1, .presence(.drawing)), .dropped(attempt: 1),
      ])
  }

  @Test func failedOpenIsADrop() async {
    let runner = WebSocketRunner(dependencies: Self.dependencies(pool: ConnectionPool([])))
    #expect(await runner.run(.open(attempt: 4)) == .dropped(attempt: 4))
  }

  @Test func closeEndsTheAttemptsSocket() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 1))
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

    _ = await runner.run(.open(attempt: 2))
    _ = await runner.run(.close(attempt: 1))
    _ = await runner.run(.send(.presence(.drawing), attempt: 2))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .presence(.drawing))
  }

  @Test func sendGoesToTheOpenSocket() async {
    let socket = makeFakeSocket()
    let runner = WebSocketRunner(
      dependencies: Self.dependencies(pool: ConnectionPool([socket.connection])))

    _ = await runner.run(.open(attempt: 1))
    #expect(await runner.run(.send(.resume(lastSeq: 2), attempt: 1)) == nil)

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 2))
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
}
