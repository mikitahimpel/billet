/// The interpreter for ``WebSocketMachine``: the one place its outputs reach services.
///
/// Events that come from the socket rather than from an output's result (`opened`, `received`,
/// `dropped`) go through `events`, one pipe, so they reach the machine in the order they happened.
/// Every event carries its attempt number; the machine discards the stale ones.
final class WebSocketRunner: Sendable {
  let events: AsyncStream<WebSocketMachine.Event>
  private let continuation: AsyncStream<WebSocketMachine.Event>.Continuation
  private let dependencies: WebSocketDependencies
  private let slot = ConnectionSlot()

  init(dependencies: WebSocketDependencies) {
    let pipe = AsyncStream.makeStream(of: WebSocketMachine.Event.self)
    self.events = pipe.stream
    self.continuation = pipe.continuation
    self.dependencies = dependencies
  }

  func run(_ output: WebSocketMachine.Output) async -> WebSocketMachine.Event? {
    switch output {
    case .open(let attempt):
      do {
        let connection = try await dependencies.open()
        await slot.install(connection, for: attempt)
        continuation.yield(.opened(attempt: attempt))
        let reader = Task { [continuation] in
          for await message in connection.messages {
            continuation.yield(.received(attempt: attempt, message))
          }
          continuation.yield(.dropped(attempt: attempt))
        }
        await slot.attach(reader: reader, to: attempt)
        return nil
      } catch {
        return .dropped(attempt: attempt)
      }

    case .close(let attempt):
      if let connection = await slot.release(attempt) {
        await connection.close()
      }
      return nil

    case .send(let message, let attempt):
      guard let connection = await slot.connection(for: attempt) else { return nil }
      do {
        try await connection.send(message)
        return nil
      } catch {
        return .dropped(attempt: attempt)
      }

    case .startConnectTimeout(let attempt):
      await dependencies.sleep(WebSocketMachine.connectTimeout)
      return .connectTimedOut(attempt: attempt)

    case .scheduleRetry(let failures, let attempt):
      await dependencies.sleep(WebSocketMachine.retryDelay(afterFailures: failures))
      return .retryElapsed(attempt: attempt)

    case .deliver(let message):
      await dependencies.deliver(message)
      return nil
    }
  }
}

/// The open sockets and their readers, by attempt number.
actor ConnectionSlot {
  private struct Entry {
    var connection: WebSocketConnection
    var reader: Task<Void, Never>?
  }

  private var entries: [Int: Entry] = [:]

  func install(_ connection: WebSocketConnection, for attempt: Int) {
    entries[attempt] = Entry(connection: connection, reader: nil)
  }

  func attach(reader: Task<Void, Never>, to attempt: Int) {
    if entries[attempt] != nil {
      entries[attempt]?.reader = reader
    } else {
      reader.cancel()
    }
  }

  func connection(for attempt: Int) -> WebSocketConnection? {
    entries[attempt]?.connection
  }

  /// Forgets the attempt's socket and stops reading it. The caller closes it.
  func release(_ attempt: Int) -> WebSocketConnection? {
    guard let entry = entries.removeValue(forKey: attempt) else { return nil }
    entry.reader?.cancel()
    return entry.connection
  }
}
