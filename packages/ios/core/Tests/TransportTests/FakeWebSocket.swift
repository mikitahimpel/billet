import Wire

@testable import Transport

/// A connection whose incoming messages the test controls and whose sent messages it can read.
struct FakeSocket: Sendable {
  let connection: WebSocketConnection
  let incoming: AsyncStream<ServerMessage>.Continuation
  let sent: AsyncStream<ClientMessage>
}

func makeFakeSocket() -> FakeSocket {
  let incoming = AsyncStream.makeStream(of: ServerMessage.self)
  let sent = AsyncStream.makeStream(of: ClientMessage.self)
  let connection = WebSocketConnection(
    messages: incoming.stream,
    send: { message in _ = sent.continuation.yield(message) },
    close: { incoming.continuation.finish() }
  )
  return FakeSocket(connection: connection, incoming: incoming.continuation, sent: sent.stream)
}

/// Hands out the prepared connections in order.
actor ConnectionPool {
  private var remaining: [WebSocketConnection]

  init(_ connections: [WebSocketConnection]) {
    remaining = connections
  }

  func next() -> WebSocketConnection? {
    remaining.isEmpty ? nil : remaining.removeFirst()
  }
}
