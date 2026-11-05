import Foundation
import Synchronization
import Wire

extension WebSocketConnection {
  /// Opens a socket over `URLSession` and returns once the server has answered a ping.
  ///
  /// A frame that does not decode as a ``ServerMessage`` is skipped.
  public static func urlSession(
    _ request: URLRequest, session: URLSession
  ) async throws(TransportError) -> WebSocketConnection {
    let task = session.webSocketTask(with: request)
    task.resume()
    do {
      // Cancelling the connect cancels the task, so a stuck handshake does not outlive its attempt.
      try await withTaskCancellationHandler {
        try await task.ping()
      } onCancel: {
        task.cancel(with: .goingAway, reason: nil)
      }
    } catch {
      task.cancel(with: .goingAway, reason: nil)
      throw .network(error.localizedDescription)
    }

    let messages = AsyncStream<ServerMessage> { continuation in
      let reader = Task {
        while !Task.isCancelled {
          do {
            let frame = try await task.receive()
            let data: Data
            switch frame {
            case .data(let bytes): data = bytes
            case .string(let text): data = Data(text.utf8)
            @unknown default: continue
            }
            if let message = try? JSONDecoder().decode(ServerMessage.self, from: data) {
              continuation.yield(message)
            }
          } catch {
            break
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in reader.cancel() }
    }

    return WebSocketConnection(
      messages: messages,
      send: { message throws(TransportError) in
        let data: Data
        do {
          data = try JSONEncoder().encode(message)
        } catch {
          throw .encoding
        }
        do {
          try await task.send(.string(String(decoding: data, as: UTF8.self)))
        } catch {
          throw .network(error.localizedDescription)
        }
      },
      close: { task.cancel(with: .goingAway, reason: nil) }
    )
  }
}

extension URLSessionWebSocketTask {
  /// `sendPing` can call its handler a second time, with an error, when the task is cancelled after
  /// the pong; only the first answer resumes.
  fileprivate func ping() async throws {
    let answered = Mutex(false)
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      sendPing { error in
        let first = answered.withLock { done in
          defer { done = true }
          return !done
        }
        guard first else { return }
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}
