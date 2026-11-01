import BilletKit
import Delivery
import DesignSystem
import FeatureInbox
import Foundation
import Observation
import Persistence
import Pet
import WidgetBridge
import Wire

/// A live pairing: the room connection, the cat's state and the notes kept for it.
///
/// It outlives the screens on top of it, so a note arriving on any tab is both kept and carried in
/// by the cat.
@MainActor
@Observable
final class PairSession {
  let room: DemoRoom
  let store: Store<HomeMachine>
  let shop: ShopStore
  let renovator: RoomRenovator
  /// True when the partner is the scripted one from Labs.
  let isFakePartner: Bool
  /// The lab switches. Each experiment checks its own.
  let labs: WidgetFeaturesModel
  private(set) var status = NoteDelivery.Status.connecting
  /// True once this connection has reached the room, which makes a later `.connecting` a reconnect.
  private(set) var hasConnected = false
  private(set) var notes: [NoteRecord] = []
  private(set) var notesFailedToLoad = false
  private(set) var play: PairPlay
  /// Counts up each time the partner reacts to a note this device sent, and holds that reaction.
  private(set) var reactionsSeen = 0
  private(set) var lastReaction: Reaction?
  /// True while the shared treat falls onto the cat.
  private(set) var treatFalling = false

  /// Called on each status change.
  @ObservationIgnored var onStatus: ((NoteDelivery.Status) -> Void)?

  @ObservationIgnored private let delivery: NoteDelivery
  @ObservationIgnored private let archive: NoteArchive
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var connection: Task<Void, Never>?
  @ObservationIgnored private var lastSave: Task<Void, Never>?

  init(
    room: DemoRoom,
    delivery: NoteDelivery,
    archive: NoteArchive,
    shop: ShopStore,
    now: @escaping @Sendable () -> Date = { .now },
    isFakePartner: Bool = false,
    labs: WidgetFeaturesModel = WidgetFeaturesModel(store: nil)
  ) {
    self.isFakePartner = isFakePartner
    self.labs = labs
    self.room = room
    self.delivery = delivery
    self.archive = archive
    self.shop = shop
    renovator = RoomRenovator(store: shop)
    self.now = now
    play = PairPlay(device: room.device)
    store = Store(initial: HomeMachine.State()) { await HomeRunner.run($0, delivery: delivery) }
  }

  /// Opens the room connection unless it is already open.
  func connect() {
    guard connection == nil else { return }
    let updates = delivery.updates()
    connection = Task { [weak self] in
      for await update in updates {
        guard let self, !Task.isCancelled else { return }
        await self.apply(update)
      }
    }
  }

  /// Closes the room connection.
  func disconnect() {
    connection?.cancel()
    connection = nil
  }

  /// Tells the room about a push token that changed while this connection is open.
  func pushTokenChanged() async {
    await delivery.pushTokenChanged()
  }

  func loadNotes() async {
    do {
      let stored = try await archive.notes()
      // A note can arrive while this loads, and its save may not have landed yet.
      let storedIDs = Set(stored.map(\.id))
      notes = (notes.filter { !storedIDs.contains($0.id) } + stored)
        .sorted { $0.date > $1.date }
      notesFailedToLoad = false
    } catch {
      notesFailedToLoad = true
    }
  }

  /// Returns once every note kept so far has reached the archive.
  func savesFinished() async {
    await lastSave?.value
  }

  func send(_ strokes: [Stroke]) {
    let id = UUID()
    store.send(.drawingSent(strokes, id: id))
    keep(strokes, .sent, id: id)
  }

  /// Reacts to a note the partner sent, here at once and then in the room. A note this device
  /// sent itself cannot be reacted to.
  func react(to note: NoteRecord, _ reaction: Reaction) {
    guard note.direction == .received else { return }
    play.reactionGiven(to: note.id, reaction)
    Task { [delivery] in await delivery.react(note.id, reaction) }
  }

  /// Pets the cat here and tells the partner's phone.
  func pet() {
    play.petGiven()
    let at = TreatDay.timestamp(for: now(), calendar: .current)
    Task { [delivery] in await delivery.play(.pet, at) }
  }

  /// Names the cat here at once and tells the room. If the partner named it first, the room's
  /// name replaces this one.
  func nameCat(_ raw: String) {
    guard let name = CatName.clean(raw) else { return }
    play.named(name)
    Task { [delivery] in await delivery.nameCat(name) }
  }

  func giveTreat(on day: String) {
    applyTreat { _ = $0.treatGiven(on: day) }
    let at = TreatDay.timestamp(for: now(), calendar: .current)
    Task { [delivery] in await delivery.play(.treat, at) }
  }

  /// Changes the play state, and drops the treat on the cat when that made today's treat shared.
  private func applyTreat(_ change: (inout PairPlay) -> Void) {
    let day = TreatDay.key(for: now(), calendar: .current)
    let before = play.status(on: day)
    change(&play)
    guard before != .fed, play.status(on: day) == .fed else { return }
    treatFalling = true
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      treatFalling = false
    }
  }

  private func apply(_ update: NoteDelivery.Update) async {
    switch update {
    case .status(let newStatus):
      switch newStatus {
      case .partnerAway, .partnerHere: hasConnected = true
      case .connecting, .refused: break
      }
      status = newStatus
      store.send(.pet(.partnerPresence(newStatus == .partnerHere)))
      onStatus?(newStatus)
    case .note(let strokes, let id):
      store.send(.noteReceived(strokes))
      keep(strokes, .received, id: id)
    case .reactions(let table):
      let changed = play.reactionsReceived(table)
      // Replayed ones arrive before the first room frame, and are shown without a flourish.
      guard hasConnected else { return }
      let mine = Set(notes.filter { $0.direction == .sent }.map(\.id))
      if let (_, reaction) = changed.first(where: { mine.contains($0.key) }) {
        lastReaction = reaction
        reactionsSeen += 1
      }
    case .partnerPetted:
      play.petReceived()
    case .treats(let days):
      applyTreat { $0.treatsReceived(days) }
    case .catName(let name):
      play.named(name)
    }
  }

  private func keep(_ strokes: [Stroke], _ direction: NoteRecord.Direction, id: UUID) {
    let note = NoteRecord(id: id, direction: direction, date: now(), strokes: strokes)
    // Shown straight away: a failed save costs the note after a restart, not on screen.
    notes.insert(note, at: 0)
    let previous = lastSave
    lastSave = Task { [archive] in
      await previous?.value
      _ = try? await archive.add(note)
    }
  }
}
