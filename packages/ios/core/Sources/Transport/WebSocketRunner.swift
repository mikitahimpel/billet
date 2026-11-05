import Wire

/// The interpreter for ``WebSocketMachine``: the one place its outputs reach services.
///
/// Events that come from the socket rather than from an output's result (`opened`, `received`,
/// `dropped`) go through `events`, one pipe, so they reach the machine in the order they happened.
/// Every event carries its attempt number; the machine discards the stale ones.
///
/// Outputs are not ordered: `Store` runs each in its own task, so a `deliver` may overtake an
/// earlier one. A caller that needs strokes in `seq` order must sort them. Sends are the
/// exception: every message goes through one outbox and one writer, so they leave in the order
/// they were enqueued. A live stroke's points must never overtake its begin. `Resume` is enqueued
/// when the socket is installed, before `opened` is reported, so it goes first.
///
/// A `close` also stops what the attempt has in flight: a connect that is still opening is
/// cancelled, and its timers are stopped.
final class WebSocketRunner: Sendable {
  let events: AsyncStream<WebSocketMachine.Event>
  private let continuation: AsyncStream<WebSocketMachine.Event>.Continuation
  private let dependencies: WebSocketDependencies
  private let slot = ConnectionSlot()
  private let outbox: AsyncStream<Outgoing>.Continuation
  private let writer: Task<Void, Never>

  private struct Outgoing: Sendable {
    let message: ClientMessage
    let attempt: Int
  }

  init(dependencies: WebSocketDependencies) {
    let pipe = AsyncStream.makeStream(of: WebSocketMachine.Event.self)
    self.events = pipe.stream
    self.continuation = pipe.continuation
    self.dependencies = dependencies
    let outgoing = AsyncStream.makeStream(of: Outgoing.self)
    self.outbox = outgoing.continuation
    self.writer = Task { [slot, continuation = pipe.continuation] in
      for await item in outgoing.stream {
        // A message for an attempt that has ended is dropped, as live strokes are offline.
        guard let connection = await slot.connection(for: item.attempt) else { continue }
        do {
          try await connection.send(item.message)
        } catch {
          continuation.yield(.dropped(attempt: item.attempt))
        }
      }
    }
  }

  /// Queues `message` for the socket of `attempt`, behind everything queued before it. Never
  /// waits, so a caller on the main actor keeps its order.
  func enqueue(_ message: ClientMessage, attempt: Int) {
    outbox.yield(Outgoing(message: message, attempt: attempt))
  }

  /// Closes every socket and stops all work in flight. The client calls it when it goes away.
  func shutdown() async {
    outbox.finish()
    writer.cancel()
    for connection in await slot.releaseAll() {
      await connection.close()
    }
    continuation.finish()
  }

  func run(_ output: WebSocketMachine.Output) async -> WebSocketMachine.Event? {
    switch output {
    case .open(let attempt, let resumeFrom):
      let opening = Task { [dependencies] in try await dependencies.open() }
      await slot.track(opening: opening, for: attempt)
      do {
        let connection = try await opening.value
        await slot.install(connection, for: attempt)
        await slot.cancelTimer(for: attempt)
        enqueue(
          .resume(
            lastSeq: resumeFrom, activity: dependencies.followsActivity ? true : nil,
            lastReactionRev: await dependencies.lastReactionRev(),
            shop: dependencies.followsShop ? true : nil,
            lists: dependencies.followsLists ? true : nil,
            moods: dependencies.followsMoods ? true : nil),
          attempt: attempt)
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
      enqueue(message, attempt: attempt)
      return nil

    case .startConnectTimeout(let attempt):
      return await timer(
        .connectTimedOut(attempt: attempt), after: WebSocketMachine.connectTimeout, for: attempt)

    case .startStabilityTimer(let attempt):
      return await timer(
        .stable(attempt: attempt), after: WebSocketMachine.stableAfter, for: attempt)

    case .scheduleRetry(let failures, let attempt):
      let delay = WebSocketMachine.retryDelay(afterFailures: failures) * dependencies.jitter()
      await dependencies.sleep(delay)
      return .retryElapsed(attempt: attempt)

    case .deliver(let message):
      await dependencies.deliver(message)
      return nil
    }
  }

  /// Sleeps, then reports `event`, unless the attempt ended and stopped the timer first.
  private func timer(
    _ event: WebSocketMachine.Event, after delay: Duration, for attempt: Int
  ) async -> WebSocketMachine.Event? {
    let sleeping = Task { [dependencies] in await dependencies.sleep(delay) }
    await slot.track(timer: sleeping, for: attempt)
    await sleeping.value
    return sleeping.isCancelled ? nil : event
  }
}

/// The open sockets, their readers and the work still in flight, by attempt number.
actor ConnectionSlot {
  private struct Entry {
    var connection: WebSocketConnection
    var reader: Task<Void, Never>?
  }

  private var entries: [Int: Entry] = [:]
  private var openings: [Int: Task<WebSocketConnection, any Error>] = [:]
  private var timers: [Int: Task<Void, Never>] = [:]

  func track(opening: Task<WebSocketConnection, any Error>, for attempt: Int) {
    openings[attempt] = opening
  }

  /// Replaces the attempt's timer, stopping the one before it.
  func track(timer: Task<Void, Never>, for attempt: Int) {
    timers[attempt]?.cancel()
    timers[attempt] = timer
  }

  func cancelTimer(for attempt: Int) {
    timers.removeValue(forKey: attempt)?.cancel()
  }

  func install(_ connection: WebSocketConnection, for attempt: Int) {
    openings.removeValue(forKey: attempt)
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

  /// Forgets the attempt's socket and stops reading it, cancels a connect still in flight and
  /// stops its timers. The caller closes the socket.
  func release(_ attempt: Int) -> WebSocketConnection? {
    openings.removeValue(forKey: attempt)?.cancel()
    timers.removeValue(forKey: attempt)?.cancel()
    guard let entry = entries.removeValue(forKey: attempt) else { return nil }
    entry.reader?.cancel()
    return entry.connection
  }

  /// Everything above for every attempt. The caller closes the sockets.
  func releaseAll() -> [WebSocketConnection] {
    for opening in openings.values { opening.cancel() }
    for timer in timers.values { timer.cancel() }
    for entry in entries.values { entry.reader?.cancel() }
    let connections = entries.values.map(\.connection)
    openings = [:]
    timers = [:]
    entries = [:]
    return connections
  }
}
