import Delivery
import DesignSystem
import FeatureInbox
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
    /// When it was sent, which the cat's life counts it at.
    var at: String?
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
    /// For an `adopt` play: `pick`, `hold` or `adopt`, and its cat or finger.
    var move: String?
    var cat: String?
    var holding: Bool?
    /// For a `light` play: where the switch now stands.
    var light: String?
    /// For a `daily` play: the drawing of the day.
    var ink: String?
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
    let from: String?
    let at: String?
    let events: [LifeFrameEvent]?
    let move: String?
    let cat: String?
    let holding: Bool?
    let light: String?
    let day: String?
    let prompt: PromptFrame?
    let prompts: [String: PromptFrame]?
    let mine: DrawingFrame?
    let theirs: DrawingFrame?
    let theirsDrawn: Bool?
  }

  private struct PromptFrame: Decodable {
    let id: String
    let text: String

    var prompt: DailyPromptText { DailyPromptText(id: id, text: text) }
  }

  private struct DrawingFrame: Decodable {
    let ink: String

    var strokes: [Stroke]? { try? NoteInk.decode(ink) }
  }

  private struct LifeFrameEvent: Decodable {
    let id: String
    let kind: String
    let by: String
    let at: String

    var event: LifeEvent? {
      guard let uuid = UUID(uuidString: id), let kind = LifeEvent.Kind(rawValue: kind),
        let date = LiveDelivery.date(at)
      else { return nil }
      return LifeEvent(id: uuid, kind: kind, by: by, at: date)
    }
  }

  /// The most life frames kept for a room that has not acked them, as an older room never does.
  private static let longestLifeOutbox = 50

  private static let refusedStatusCodes: Set<Int> = [400, 403]
  private static let longestBackoff = 15

  private let url: URL
  private var outbox: [Outgoing] = []
  /// Plays that wait for the server's ack: treats and the cat's name.
  private var treatOutbox: [OutgoingPlay] = []
  /// Life events that wait for the server's ack, sent again after a reconnect.
  private var lifeOutbox: [OutgoingPlay] = []
  private var receivedIDs: Set<String> = []
  private var openSocket: URLSessionWebSocketTask?

  init(url: URL) {
    self.url = url
  }

  func send(_ strokes: [Stroke], id: UUID) async {
    guard let ink = try? NoteInk.encode(strokes) else { return }
    let note = Outgoing(
      id: id.uuidString.lowercased(), ink: ink,
      at: TreatDay.timestamp(for: .now, calendar: .current))
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
    case .treat, .feed, .play, .sleep, .shoo:
      treatOutbox.append(frame)
      if let openSocket { await Self.write(frame, to: openSocket) }
    }
  }

  /// A pet is sent like any other: once, now. Feeding, a game and bedtime wait for the ack.
  func life(_ event: LifeEvent) async {
    guard let kind = event.kind.playKind else { return }
    let frame = OutgoingPlay(
      id: event.id.uuidString.lowercased(), kind: kind.rawValue,
      at: TreatDay.timestamp(for: event.at, calendar: .current))
    switch kind {
    case .pet:
      if let openSocket { await Self.write(frame, to: openSocket) }
    case .treat, .feed, .play, .sleep, .shoo:
      lifeOutbox = Array((lifeOutbox + [frame]).suffix(Self.longestLifeOutbox))
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

  /// A new name over the old one goes like a treat: kept until acked and sent again after a
  /// reconnect. The room keeps the last one and tells both phones.
  func renameCat(_ name: String) async {
    let at = TreatDay.timestamp(for: .now, calendar: .current)
    let frame = OutgoingPlay(
      id: UUID().uuidString.lowercased(), kind: "rename", at: at, name: name)
    treatOutbox.append(frame)
    if let openSocket { await Self.write(frame, to: openSocket) }
  }

  /// A press of the light switch waits for the ack and is sent again after a reconnect. Only the
  /// latest press is kept: an earlier one no longer matters.
  func switchLight(_ light: RoomLight) async {
    let at = TreatDay.timestamp(for: .now, calendar: .current)
    var frame = OutgoingPlay(id: UUID().uuidString.lowercased(), kind: "light", at: at)
    frame.light = light.rawValue
    treatOutbox.removeAll { $0.kind == "light" }
    treatOutbox.append(frame)
    if let openSocket { await Self.write(frame, to: openSocket) }
  }

  /// A finger on the cat only matters now, so it is dropped when the socket is down. A pick and
  /// an adoption wait for the ack and are sent again after a reconnect.
  func adopt(_ move: AdoptionMove) async {
    let at = TreatDay.timestamp(for: .now, calendar: .current)
    var frame = OutgoingPlay(id: UUID().uuidString.lowercased(), kind: "adopt", at: at)
    switch move {
    case .pick(let cat):
      frame.move = "pick"
      frame.cat = cat?.rawValue
    case .hold(let holding):
      frame.move = "hold"
      frame.holding = holding
      if let openSocket { await Self.write(frame, to: openSocket) }
      return
    case .adopt(let cat):
      frame.move = "adopt"
      frame.cat = cat.rawValue
    }
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

  /// The drawing of the day goes like a treat: kept until acked and sent again after a reconnect.
  /// The room keeps the first drawing of a day, so a repeat changes nothing.
  func drawDaily(_ strokes: [Stroke], at time: String) async {
    guard let ink = try? NoteInk.encode(strokes) else { return }
    let frame = OutgoingPlay(
      id: UUID().uuidString.lowercased(), kind: "daily", at: time, ink: ink)
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
        for treat in treatOutbox + lifeOutbox {
          await Self.write(treat, to: task)
        }
      }
    case "ack":
      outbox.removeAll { $0.id == frame.id }
      treatOutbox.removeAll { $0.id == frame.id }
      lifeOutbox.removeAll { $0.id == frame.id }
    case "play":
      guard frame.kind == PlayKind.pet.rawValue, let id = frame.id, receivedIDs.insert(id).inserted
      else { return }
      updates.yield(.partnerPetted)
      if let uuid = UUID(uuidString: id) {
        let at = frame.at.flatMap(Self.date) ?? .now
        updates.yield(.life([LifeEvent(id: uuid, kind: .pet, by: frame.from ?? "", at: at)]))
      }
    case "life":
      updates.yield(.life((frame.events ?? []).compactMap(\.event)))
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
    case "light":
      if let light = frame.light.flatMap(RoomLight.init(rawValue:)) {
        updates.yield(.roomLight(light))
      }
    case "daily-prompts":
      updates.yield(.dailyPrompts((frame.prompts ?? [:]).mapValues(\.prompt)))
    case "daily":
      guard let day = frame.day, let prompt = frame.prompt?.prompt else { return }
      updates.yield(
        .daily(
          DailyEntry(
            day: day, prompt: prompt, mine: frame.mine?.strokes, theirs: frame.theirs?.strokes,
            theirsDrawn: frame.theirsDrawn ?? false)))
    case "adopt":
      guard let id = frame.id, receivedIDs.insert(id).inserted,
        let move = Self.adoption(frame)
      else { return }
      updates.yield(.partnerAdoption(move))
    case "note":
      guard let id = frame.id, let ink = frame.ink, let noteID = UUID(uuidString: id),
        receivedIDs.insert(id).inserted, let strokes = try? NoteInk.decode(ink)
      else { return }
      NoteImage.saveLatest(strokes)
      WidgetCenter.shared.reloadAllTimelines()
      updates.yield(.note(strokes, id: noteID))
      updates.yield(.life([LifeEvent(id: noteID, kind: .note, by: frame.from ?? "", at: .now)]))
    default:
      break
    }
  }

  /// A room time, with or without fractions of a second.
  static func date(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text)
  }

  /// The partner's move in an `adopt` frame, or `nil` when it is malformed.
  private static func adoption(_ frame: Frame) -> AdoptionMove? {
    switch frame.move {
    case "pick": .pick(frame.cat.flatMap(AdoptionCat.init(rawValue:)))
    case "hold": frame.holding.map(AdoptionMove.hold)
    case "adopt": frame.cat.flatMap(AdoptionCat.init(rawValue:)).map(AdoptionMove.adopt)
    default: nil
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
