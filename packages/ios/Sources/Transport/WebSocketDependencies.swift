import Wire

/// One open socket. `messages` ends when the socket drops or closes.
public struct WebSocketConnection: Sendable {
  public var messages: AsyncStream<ServerMessage>
  public var send: @Sendable (ClientMessage) async throws(TransportError) -> Void
  public var close: @Sendable () async -> Void

  public init(
    messages: AsyncStream<ServerMessage>,
    send: @escaping @Sendable (ClientMessage) async throws(TransportError) -> Void,
    close: @escaping @Sendable () async -> Void
  ) {
    self.messages = messages
    self.send = send
    self.close = close
  }
}

public struct WebSocketDependencies: Sendable {
  /// Opens a socket, returning once its handshake has finished.
  public var open: @Sendable () async throws(TransportError) -> WebSocketConnection
  public var sleep: @Sendable (Duration) async -> Void
  /// Receives each server message while connected.
  public var deliver: @Sendable (ServerMessage) async -> Void

  public init(
    open: @escaping @Sendable () async throws(TransportError) -> WebSocketConnection,
    sleep: @escaping @Sendable (Duration) async -> Void,
    deliver: @escaping @Sendable (ServerMessage) async -> Void
  ) {
    self.open = open
    self.sleep = sleep
    self.deliver = deliver
  }
}
