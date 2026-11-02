import Delivery
import DesignSystem
import Foundation
import Ink
import Pet
import WidgetKit
import Wire

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

  private struct PushToken: Encodable, Sendable {
    var type = "push-token"
    let token: String
  }

  private struct OutgoingPlay: Encodable, Sendable {
    var type = "play"
    let id: String
    let kind: String
    let at: String
    var name: String?
    var note: String?
    var reaction: String?
  }

  private struct Frame: Decodable {
    let type: String
    let partnerPresent: Bool?
    let id: String?
    let ink: String?
    let kind: String?
    let days: [String: [String]]?
    let name: String?
    let reactions: [String: String]?
  }

  private static let refusedStatusCodes: Set<Int> = [400, 403]
  private static let longestBackoff = 15

  private let url: URL
  private var outbox: [Outgoing] = []
  /// Plays that wait for the server's ack: treats and the cat's name.
  private var treatOutbox: [OutgoingPlay] = []
  private var receivedIDs: Set<String> = []
  private var openSocket: URLSessionWebSocketTask?

  init(url: URL) {
    self.url = url
  }

  func send(_ strokes: [Stroke], id: UUID) async {
    guard let ink = try? NoteInk.encode(strokes) else { return }
    let note = Outgoing(id: id.uuidString.lowercased(), ink: ink)
    outbox.append(note)
    if let openSocket {
      await Self.write(note, to: openSocket)
    }
  }

  /// Tells the room where to send pushes. Also runs on every connect, so a token that arrives
  /// while offline still reaches the room.
  func sendPushToken() async {
    guard let openSocket, let token = DemoRoom.pushToken() else { return }
    await Self.write(PushToken(token: token), to: openSocket)
  }

  /// A pet only matters now, so it is dropped when the socket is down. A treat waits for the ack
  /// and is sent again after a reconnect.
  func play(_ kind: PlayKind, at time: String) async {
    let frame = OutgoingPlay(id: UUID().uuidString.lowercased(), kind: kind.rawValue, at: time)
    switch kind {
    case .pet:
      if let openSocket { await Self.write(frame, to: openSocket) }
    case .treat:
      treatOutbox.append(frame)
      if let openSocket { await Self.write(frame, to: openSocket) }
    }
  }

  /// The name goes like a treat: kept until acked and sent again after a reconnect.
  func nameCat(_ name: String) async {
    let at = TreatDay.timestamp(for: .now, calendar: .current)
    let frame = OutgoingPlay(
      id: UUID().uuidString.lowercased(), kind: "name", at: at, name: name)
    treatOutbox.append(frame)
    if let openSocket { await Self.write(frame, to: openSocket) }
  }

  /// A reaction goes like a treat: kept until acked and sent again after a reconnect.
  func react(to note: UUID, _ reaction: Reaction) async {
    let at = TreatDay.timestamp(for: .now, calendar: .current)
    let frame = OutgoingPlay(
      id: UUID().uuidString.lowercased(), kind: "react", at: at,
      note: note.uuidString.lowercased(), reaction: reaction.rawValue)
    treatOutbox.append(frame)
    if let openSocket { await Self.write(frame, to: openSocket) }
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
        await sendPushToken()
        for note in outbox {
          await Self.write(note, to: task)
        }
        for treat in treatOutbox {
          await Self.write(treat, to: task)
        }
      }
    case "ack":
      outbox.removeAll { $0.id == frame.id }
      treatOutbox.removeAll { $0.id == frame.id }
    case "play":
      guard frame.kind == PlayKind.pet.rawValue, let id = frame.id, receivedIDs.insert(id).inserted
      else { return }
      updates.yield(.partnerPetted)
    case "treats":
      updates.yield(.treats((frame.days ?? [:]).mapValues(Set.init)))
    case "reactions":
      var table: [UUID: Reaction] = [:]
      for (note, name) in frame.reactions ?? [:] {
        if let id = UUID(uuidString: note), let reaction = Reaction(rawValue: name) {
          table[id] = reaction
        }
      }
      updates.yield(.reactions(table))
    case "name":
      if let name = frame.name { updates.yield(.catName(name)) }
    case "note":
      guard let id = frame.id, let ink = frame.ink, let noteID = UUID(uuidString: id),
        receivedIDs.insert(id).inserted, let strokes = try? NoteInk.decode(ink)
      else { return }
      NoteImage.saveLatest(strokes)
      WidgetCenter.shared.reloadAllTimelines()
      updates.yield(.note(strokes, id: noteID))
    default:
      break
    }
  }

  /// A failed write surfaces as a failed receive, which reconnects and resends.
  private static func write(
    _ frame: some Encodable & Sendable, to task: URLSessionWebSocketTask
  ) async {
    guard let data = try? JSONEncoder().encode(frame) else { return }
    try? await task.send(.string(String(decoding: data, as: UTF8.self)))
  }
}
