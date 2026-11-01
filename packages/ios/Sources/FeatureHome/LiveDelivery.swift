import Foundation
import Ink
import Wire

/// A note's `ink` field: base64 of the compact stroke JSON.
enum NoteInk {
  /// A socket frame carries far more than a push, so drawings keep their detail.
  private static let budget = 256 * 1024

  static func encode(_ strokes: [Stroke]) throws -> String {
    let compact = try InkEncoder.encodeWithinBudget(
      strokes, parameters: InkEncoder.Parameters(budget: budget))
    return try JSONEncoder().encode(compact).base64EncodedString()
  }

  static func decode(_ ink: String) throws -> [Stroke] {
    guard let data = Data(base64Encoded: ink) else { throw CocoaError(.coderReadCorrupt) }
    return try InkDecoder.decode(JSONDecoder().decode(CompactStrokes.self, from: data))
  }
}

/// One device's socket to its room, kept open only while ``run(_:)`` runs.
///
/// Notes stay in the outbox until the server acks them and are sent again after a reconnect. The
/// server ignores IDs it has already stored, so repeats are harmless.
actor LiveDelivery {
  private struct Outgoing: Encodable, Sendable {
    var type = "note"
    let id: String
    let ink: String
  }

  private struct Frame: Decodable {
    let type: String
    let partnerPresent: Bool?
    let id: String?
    let ink: String?
  }

  private static let refusedStatusCodes: Set<Int> = [400, 403]
  private static let longestBackoff = 15

  private let url: URL
  private var outbox: [Outgoing] = []
  private var receivedIDs: Set<String> = []
  private var openSocket: URLSessionWebSocketTask?

  init(url: URL) {
    self.url = url
  }

  func send(_ strokes: [Stroke]) async {
    guard let ink = try? NoteInk.encode(strokes) else { return }
    let note = Outgoing(id: UUID().uuidString.lowercased(), ink: ink)
    outbox.append(note)
    if let openSocket {
      await Self.write(note, to: openSocket)
    }
  }

  /// Connects and reconnects with backoff until cancelled or the server refuses this device.
  func run(_ updates: AsyncStream<NoteDelivery.Update>.Continuation) async {
    var failures = 0
    while !Task.isCancelled {
      updates.yield(.status(.connecting))
      let task = URLSession.shared.webSocketTask(with: url)
      task.resume()
      let opened = await withTaskCancellationHandler {
        await receive(from: task, updates)
      } onCancel: {
        task.cancel(with: .goingAway, reason: nil)
      }
      if openSocket === task { openSocket = nil }
      task.cancel(with: .goingAway, reason: nil)

      if let response = task.response as? HTTPURLResponse,
        Self.refusedStatusCodes.contains(response.statusCode)
      {
        updates.yield(.status(.refused))
        return
      }
      failures = opened ? 1 : failures + 1
      try? await Task.sleep(for: .seconds(min(Self.longestBackoff, 1 << min(failures, 4))))
    }
  }

  /// Reads until the socket fails. Returns whether the server ever answered.
  private func receive(
    from task: URLSessionWebSocketTask,
    _ updates: AsyncStream<NoteDelivery.Update>.Continuation
  ) async -> Bool {
    var opened = false
    while let message = try? await task.receive() {
      opened = true
      let data: Data
      switch message {
      case .data(let bytes): data = bytes
      case .string(let text): data = Data(text.utf8)
      @unknown default: continue
      }
      guard let frame = try? JSONDecoder().decode(Frame.self, from: data) else { continue }
      await handle(frame, from: task, updates)
    }
    return opened
  }

  private func handle(
    _ frame: Frame,
    from task: URLSessionWebSocketTask,
    _ updates: AsyncStream<NoteDelivery.Update>.Continuation
  ) async {
    switch frame.type {
    case "room":
      updates.yield(.status(frame.partnerPresent == true ? .partnerHere : .partnerAway))
      if openSocket !== task {
        openSocket = task
        for note in outbox {
          await Self.write(note, to: task)
        }
      }
    case "ack":
      outbox.removeAll { $0.id == frame.id }
    case "note":
      guard let id = frame.id, let ink = frame.ink, receivedIDs.insert(id).inserted,
        let strokes = try? NoteInk.decode(ink)
      else { return }
      updates.yield(.note(strokes))
    default:
      break
    }
  }

  /// A failed write surfaces as a failed receive, which reconnects and resends.
  private static func write(_ note: Outgoing, to task: URLSessionWebSocketTask) async {
    guard let data = try? JSONEncoder().encode(note) else { return }
    try? await task.send(.string(String(decoding: data, as: UTF8.self)))
  }
}
