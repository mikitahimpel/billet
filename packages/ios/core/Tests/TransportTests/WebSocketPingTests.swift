import Testing
import Wire

@testable import Transport

@Suite @MainActor struct WebSocketPingTests {
  static let timeout = Duration.seconds(5)

  static func isConnected(_ client: WebSocketClient) -> Bool {
    if case .connected = client.state.phase { true } else { false }
  }

  @Test func anAnsweredPingKeepsTheSocket() async {
    let socket = makeFakeSocket()
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(
        pool: ConnectionPool([socket.connection]),
        sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }))
    client.connect()
    while !Self.isConnected(client) { await Task.yield() }

    #expect(await client.ping(timeout: Self.timeout))
    #expect(client.state.phase == .connected(failures: 0))
    client.disconnect()
  }

  @Test func aPingThatGoesUnansweredDropsTheSocketAndOpensAnother() async {
    let silent = makeFakeSocket()
    let dead = WebSocketConnection(
      messages: AsyncStream { _ in }, send: silent.connection.send, close: {},
      ping: { try? await Task.sleep(for: .seconds(3600)) })
    let next = makeFakeSocket()
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(
        pool: ConnectionPool([dead, next.connection])))
    client.connect()
    while !Self.isConnected(client) { await Task.yield() }

    #expect(await client.ping(timeout: Self.timeout) == false)
    var sent = next.sent.makeAsyncIterator()
    #expect(await sent.next() == .resume(lastSeq: 0))
    client.disconnect()
  }

  @Test func noPingWithoutASocket() async {
    let client = WebSocketClient(
      dependencies: WebSocketRunnerTests.dependencies(pool: ConnectionPool([])))
    #expect(await client.ping(timeout: Self.timeout) == false)
  }
}
