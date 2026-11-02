import DesignSystem
import Foundation
import Labs
import Pet
import Wire

/// How long the fake partner waits before each thing it does.
struct FakePartnerPace: Sendable {
  /// Before the partner shows as here.
  var arrival: Duration
  /// After a note is sent, before the partner opens it.
  var open: Duration
  /// After a note is sent, before the partner reacts to it.
  var reaction: Duration
  /// After a note is sent, before the partner draws one back.
  var reply: Duration
  /// After a pet, before the partner pets back.
  var petBack: Duration
  /// After a treat, before the partner gives theirs.
  var treatBack: Duration
  /// How long a sealed note from the partner stays closed. Short, so it can be watched opening.
  var sealedFor: Duration
  /// How long the partner keeps a finger on the cat.
  var holdFor: Duration
  /// The advent doors the partner has already filled when it arrives.
  var adventDoors: [Int]
  /// After a gift is wrapped, before the partner unwraps it.
  var giftOpened: Duration
  /// After the user's lamp goes out or comes back, before the partner's follows.
  var lampFollows: Duration
  /// Between the things the partner does when nobody has done anything.
  var idle: [Duration]

  static let calm = FakePartnerPace(
    arrival: .seconds(1), open: .seconds(3), reaction: .seconds(5), reply: .seconds(12),
    petBack: .seconds(2),
    treatBack: .seconds(5), sealedFor: .seconds(90), holdFor: .seconds(10),
    adventDoors: [3, 9, 15, 21], giftOpened: .seconds(6), lampFollows: .seconds(8),
    idle: [.seconds(25), .seconds(20), .seconds(35), .seconds(60)])
}

/// FAKE. A partner that lives in this app, so everything can be tried on one phone. It answers
/// what the user does and, when left alone, now and then draws a note or pets the cat.
///
/// Only the settings toggle brings it in; the real room connection never touches this file.
actor FakePartnerRoom {
  static let device = "fake-partner"
  /// Far enough from most users that the sky differs from their own.
  static let timeZoneID = "Asia/Tokyo"

  private let pace: FakePartnerPace
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (Duration) async -> Void
  private var continuation: AsyncStream<NoteDelivery.Update>.Continuation?
  private var tasks: [Task<Void, Never>] = []
  private var current: UUID?
  private var idle: Task<Void, Never>?
  private var drawn = 0
  private var gifted = 0
  private var colour = LampColour.rose
  private var lampOn = true
  private var reactions: [UUID: Reaction] = [:]

  init(
    pace: FakePartnerPace = .calm,
    now: @escaping @Sendable () -> Date = { .now },
    sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) {
    self.pace = pace
    self.now = now
    self.sleep = sleep
  }

  /// The updates the partner makes. They start when the stream is read and stop when it ends.
  nonisolated func updates() -> AsyncStream<NoteDelivery.Update> {
    AsyncStream { continuation in
      let connection = UUID()
      Task { await self.open(continuation, connection: connection) }
      continuation.onTermination = { _ in Task { await self.close(connection: connection) } }
    }
  }

  func noteSent(_ id: UUID) {
    after(pace.open) { $0.emit(.noteOpened(id)) }
    after(pace.reaction) { $0.react(to: id) }
    after(pace.reply) { $0.drawNote() }
  }

  func played(_ kind: PlayKind) {
    switch kind {
    case .pet:
      after(pace.petBack) { $0.emit(.partnerPetted) }
    case .treat:
      after(pace.treatBack) { $0.giveTreat() }
    }
  }

  /// The partner answers what the user signals: a lamp is followed, a gift is unwrapped.
  func signalled(_ signal: LabSignal) {
    switch signal {
    case .adventDoor:
      break
    case .gift(let id, _):
      after(pace.giftOpened) { $0.emit(.giftOpened(id)) }
    case .giftOpened:
      break
    case .lamp(let on):
      after(pace.lampFollows) {
        $0.lampOn = on
        $0.emitGlow()
      }
    }
  }

  /// The room confirms a name after a moment, as the real one does.
  func catNamed(_ name: String) {
    after(pace.petBack) { $0.emit(.catName(name)) }
  }

  private func open(
    _ continuation: AsyncStream<NoteDelivery.Update>.Continuation, connection: UUID
  ) {
    idle?.cancel()
    current = connection
    self.continuation = continuation
    continuation.yield(.status(.connecting))
    idle = Task { [pace, sleep] in
      await sleep(pace.arrival)
      emit(.status(.partnerHere))
      emitGlow()
      // A few doors of the advent calendar, already filled for the user.
      for (index, number) in pace.adventDoors.enumerated() {
        emit(.adventDoor(number, FakePartnerDrawings.drawing(number: index + 1)))
      }
      var step = 0
      while !Task.isCancelled, !pace.idle.isEmpty {
        await sleep(pace.idle[step % pace.idle.count])
        guard !Task.isCancelled else { return }
        idleMove(step)
        step += 1
      }
    }
  }

  /// Ends `connection`, unless a newer one has already taken over.
  private func close(connection: UUID) {
    guard current == connection else { return }
    idle?.cancel()
    idle = nil
    for task in tasks { task.cancel() }
    tasks = []
    continuation = nil
    current = nil
  }

  private func after(
    _ delay: Duration, _ action: @escaping @Sendable (isolated FakePartnerRoom) async -> Void
  ) {
    tasks.append(
      Task { [sleep] in
        await sleep(delay)
        guard !Task.isCancelled else { return }
        await action(self)
      })
  }

  private func idleMove(_ step: Int) {
    switch step % 7 {
    case 0: drawNote()
    case 1: emit(.partnerPetted)
    case 2: giveTreat()
    case 3: sealNote()
    case 4: holdCat()
    case 5: changeLamp()
    default: sendGift()
    }
  }

  private func emit(_ update: NoteDelivery.Update) {
    continuation?.yield(update)
  }

  private func react(to note: UUID) {
    reactions[note] = reactions.count.isMultiple(of: 2) ? .heart : .stamp
    emit(.reactions(reactions))
  }

  private func drawNote() {
    emit(.note(FakePartnerDrawings.drawing(number: drawn), id: UUID()))
    drawn += 1
  }

  private func sendGift() {
    let items = ["treat-milk", "furniture-yarn", "treat-cookie", "furniture-lantern"]
    emit(.gift(id: UUID(), item: items[gifted % items.count]))
    gifted += 1
  }

  private func changeLamp() {
    let all = LampColour.allCases
    colour = all[((all.firstIndex(of: colour) ?? 0) + 1) % all.count]
    emitGlow()
  }

  private func emitGlow() {
    emit(.partnerGlow(PartnerGlow(colour: colour, lampOn: lampOn, timeZoneID: Self.timeZoneID)))
  }

  private func holdCat() {
    emit(.partnerHolding(true))
    after(pace.holdFor) { $0.emit(.partnerHolding(false)) }
  }

  private func sealNote() {
    let opens = now().addingTimeInterval(Double(pace.sealedFor.components.seconds))
    emit(.sealedNote(FakePartnerDrawings.drawing(number: drawn), id: UUID(), opensAt: opens))
    drawn += 1
  }

  private func giveTreat() {
    let day = TreatDay.key(for: now(), calendar: .current)
    emit(.treats([day: [Self.device]]))
  }
}

extension NoteDelivery {
  /// FAKE. Nothing leaves the device. The partner is `room`, which answers on a timer.
  static func fakePartner(device: String, room: FakePartnerRoom = FakePartnerRoom()) -> NoteDelivery
  {
    NoteDelivery(
      device: device,
      deliver: { _, id in await room.noteSent(id) },
      play: { kind, _ in await room.played(kind) },
      nameCat: { await room.catNamed($0) },
      react: { _, _ in },
      signal: { await room.signalled($0) },
      updates: { room.updates() })
  }
}

/// Small drawings the fake partner sends, made of strokes in the unit square like any note.
enum FakePartnerDrawings {
  private static let ink = ["#A5442B", "#2A5C48", "#6B3A17", "#B27C20"]

  /// The `number`th drawing, round and round.
  static func drawing(number: Int) -> [Stroke] {
    let all = [heart, house, sun, flower, cup]
    return all[number % all.count]
  }

  static let heart: [Stroke] = [
    Stroke(
      color: ink[0], width: 0.03,
      points: (0...48).map { index in
        let t = Double(index) / 48 * 2 * .pi
        let x = 16 * pow(sin(t), 3)
        let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        return Point(x: 0.5 + x / 40, y: 0.45 - y / 40)
      })
  ]

  static let house: [Stroke] = [
    Stroke(
      color: ink[2], width: 0.03,
      points: [
        Point(x: 0.25, y: 0.8), Point(x: 0.25, y: 0.5), Point(x: 0.5, y: 0.25),
        Point(x: 0.75, y: 0.5), Point(x: 0.75, y: 0.8), Point(x: 0.25, y: 0.8),
      ]),
    Stroke(
      color: ink[3], width: 0.03,
      points: [
        Point(x: 0.45, y: 0.8), Point(x: 0.45, y: 0.62), Point(x: 0.57, y: 0.62),
        Point(x: 0.57, y: 0.8),
      ]),
  ]

  static let sun: [Stroke] = {
    let disc = Stroke(
      color: ink[3], width: 0.03,
      points: (0...32).map { index in
        let t = Double(index) / 32 * 2 * .pi
        return Point(x: 0.5 + 0.14 * cos(t), y: 0.5 + 0.14 * sin(t))
      })
    let rays = (0..<8).map { index -> Stroke in
      let t = Double(index) / 8 * 2 * .pi
      return Stroke(
        color: ink[3], width: 0.025,
        points: [
          Point(x: 0.5 + 0.22 * cos(t), y: 0.5 + 0.22 * sin(t)),
          Point(x: 0.5 + 0.32 * cos(t), y: 0.5 + 0.32 * sin(t)),
        ])
    }
    return [disc] + rays
  }()

  static let flower: [Stroke] = {
    let petals = (0..<5).map { index -> Stroke in
      let t = Double(index) / 5 * 2 * .pi
      let (cx, cy) = (0.5 + 0.13 * cos(t), 0.38 + 0.13 * sin(t))
      return Stroke(
        color: ink[0], width: 0.03,
        points: (0...16).map { step in
          let a = Double(step) / 16 * 2 * .pi
          return Point(x: cx + 0.07 * cos(a), y: cy + 0.07 * sin(a))
        })
    }
    let stem = Stroke(
      color: ink[1], width: 0.03,
      points: [Point(x: 0.5, y: 0.52), Point(x: 0.52, y: 0.68), Point(x: 0.5, y: 0.88)])
    return petals + [stem]
  }()

  static let cup: [Stroke] = [
    Stroke(
      color: ink[2], width: 0.03,
      points: [
        Point(x: 0.3, y: 0.45), Point(x: 0.33, y: 0.75), Point(x: 0.6, y: 0.75),
        Point(x: 0.63, y: 0.45), Point(x: 0.3, y: 0.45),
      ]),
    Stroke(
      color: ink[2], width: 0.03,
      points: [
        Point(x: 0.63, y: 0.52), Point(x: 0.74, y: 0.54), Point(x: 0.72, y: 0.65),
        Point(x: 0.61, y: 0.66),
      ]),
    Stroke(
      color: ink[1], width: 0.02,
      points: [Point(x: 0.42, y: 0.38), Point(x: 0.45, y: 0.3), Point(x: 0.42, y: 0.22)]),
  ]
}
