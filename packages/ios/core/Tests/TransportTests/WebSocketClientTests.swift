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
    let note = Note.photo(id: NoteId("n"), author: UserId("u"), sentAt: 0, image: MediaKey("k"))
    first.incoming.yield(.noteReceived(seq: 7, note: note))
    first.incoming.finish()

    var sent = second.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 7))
    // The runner queues Resume before it reports `opened`, so the socket can see it before the
    // client's state has moved on.
    while !client.state.isConnected { await Task.yield() }
    #expect(client.state.phase == .connected(failures: 1))
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
    while !client.state.isConnected { await Task.yield() }
    client.send(.presence(.drawing))

    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 0))
    #expect(await iterator.next() == .presence(.drawing))
    client.disconnect()
  }

  @Test func messagesLeaveInTheOrderTheyWereSent() async {
    let socket = makeFakeSocket()
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(
        pool: ConnectionPool([socket.connection])))

    client.connect()
    var iterator = socket.sent.makeAsyncIterator()
    #expect(await iterator.next() == .resume(lastSeq: 0))
    let frames = (0..<200).map { ClientMessage.strokeEnd(id: $0) }
    for frame in frames { client.send(frame) }

    var received: [ClientMessage] = []
    while received.count < frames.count, let next = await iterator.next() { received.append(next) }
    #expect(received == frames)
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
    while !client.state.isConnected { await Task.yield() }
    #expect(client.state.attempt == 2)
    gate.continuation.finish()
    client.disconnect()
  }

  @Test func releasingTheClientClosesItsSocket() async {
    let socket = makeFakeSocket()
    var client: WebSocketClient? = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(
        pool: ConnectionPool([socket.connection])))
    client?.connect()
    while !(client?.state.isConnected ?? false) { await Task.yield() }

    client = nil

    // The fake finishes its incoming stream when it is closed, so reading it then ends.
    var remaining = 0
    for await _ in socket.connection.messages { remaining += 1 }
    #expect(remaining == 0)
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

extension WebSocketMachine.State {
  fileprivate var isConnected: Bool {
    if case .connected = phase { return true }
    return false
  }
}

extension WebSocketClientTests {
  @Test func theFirstConnectionResumesAfterTheSeqAlreadyHeld() async {
    let socket = makeFakeSocket()
    let pool = ConnectionPool([socket.connection])
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(pool: pool), lastSeq: 12)
    client.connect()
    var sent = socket.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 12))
    client.disconnect()
  }
}
