import Foundation
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
  /// The factor each back-off delay is multiplied by, so that many clients do not retry in step.
  public var jitter: @Sendable () -> Double
  /// Each `Resume` also asks for `ActivityUnread`, the Inbox's unread count, whenever it changes.
  public var followsActivity: Bool
  /// The last reaction `rev` already held, read as each socket opens. A `Resume` that names one
  /// asks for every reaction change after it; `nil` follows none.
  public var lastReactionRev: @Sendable () async -> Int?
  /// Each `Resume` also asks for `ShopChanged`, the pair's shop, now and whenever it changes.
  public var followsShop: Bool

  public init(
    open: @escaping @Sendable () async throws(TransportError) -> WebSocketConnection,
    sleep: @escaping @Sendable (Duration) async -> Void,
    deliver: @escaping @Sendable (ServerMessage) async -> Void,
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) },
    followsActivity: Bool = false,
    lastReactionRev: @escaping @Sendable () async -> Int? = { nil },
    followsShop: Bool = false
  ) {
    self.open = open
    self.sleep = sleep
    self.deliver = deliver
    self.jitter = jitter
    self.followsActivity = followsActivity
    self.lastReactionRev = lastReactionRev
    self.followsShop = followsShop
  }
}
