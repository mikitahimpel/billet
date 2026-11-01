import Testing
import Wire

@testable import Transport

@Suite @MainActor struct WebSocketClientTests {
  @Test func reconnectsAfterADropAndResumesFromLastSeq() async {
    let first = makeFakeSocket()
    let second = makeFakeSocket()
    let pool = ConnectionPool([first.connection, second.connection])
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(pool: pool))

    client.connect()
    let stroke = Stroke(color: "#000", width: 1, points: [Point(x: 0, y: 0)])
    first.incoming.yield(.stroke(seq: 7, stroke: stroke))
    first.incoming.finish()

    var sent = second.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 7))
    #expect(client.state.phase == .connected)
    #expect(client.state.lastSeq == 7)

    client.disconnect()
    #expect(client.state.phase == .idle)
    #expect(client.state.lastSeq == 7)
  }

  @Test func deliversServerMessagesToTheDependency() async {
    let socket = makeFakeSocket()
    let delivered = AsyncStream.makeStream(of: ServerMessage.self)
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(
        pool: ConnectionPool([socket.connection]),
        deliver: { message in _ = delivered.continuation.yield(message) }))

    client.connect()
    socket.incoming.yield(.presence(.drawing))

    var iterator = delivered.stream.makeAsyncIterator()
    #expect(await iterator.next() == .presence(.drawing))
    client.disconnect()
  }

  @Test func sendsClientMessagesWhileConnected() async {
    let socket = makeFakeSocket()
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(
        pool: ConnectionPool([socket.connection])))

    client.connect()
    while client.state.phase != .connected { await Task.yield() }
    client.send(.presence(.drawing))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .presence(.drawing))
    client.disconnect()
  }
}

@Suite @MainActor struct WebSocketClientHungConnectTests {
  @Test func aConnectThatNeverAnswersDoesNotWedgeTheClient() async {
    let gate = AsyncStream.makeStream(of: Void.self)
    let working = makeFakeSocket()
    let pool = ConnectionPool([working.connection])
    let counter = OpenCounter()
    let client = WebSocketClient(
      dependencies: WebSocketDependencies(
        open: { () async throws(TransportError) -> WebSocketConnection in
          let number = await counter.next()
          if number == 1 {
            // The first attempt hangs until the test ends.
            for await _ in gate.stream {}
            throw .network("cancelled")
          }
          guard let connection = await pool.next() else { throw .network("none") }
          return connection
        },
        sleep: { duration in
          // Only the first connect timeout fires, so only the hung attempt times out.
          if duration == WebSocketMachine.connectTimeout, await counter.nextTimeout() > 1 {
            try? await Task.sleep(for: .seconds(3600))
          }
        },
        deliver: { _ in }))

    client.connect()
    while client.state.phase != .connected { await Task.yield() }
    #expect(client.state.attempt == 2)
    gate.continuation.finish()
    client.disconnect()
  }
}

actor OpenCounter {
  private var count = 0
  private var timeouts = 0

  func nextTimeout() -> Int {
    timeouts += 1
    return timeouts
  }

  func next() -> Int {
    count += 1
    return count
  }
}
