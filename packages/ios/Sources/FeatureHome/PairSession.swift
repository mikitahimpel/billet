import BilletKit
import Delivery
import FeatureInbox
import Foundation
import Observation
import Persistence
import Pet
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
  private(set) var status = NoteDelivery.Status.connecting
  /// True once this connection has reached the room, which makes a later `.connecting` a reconnect.
  private(set) var hasConnected = false
  private(set) var notes: [NoteRecord] = []
  private(set) var notesFailedToLoad = false
  private(set) var play: PairPlay
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
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.room = room
    self.delivery = delivery
    self.archive = archive
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
    store.send(.drawingSent(strokes))
    keep(strokes, .sent)
  }

  /// Pets the cat here and tells the partner's phone.
  func pet() {
    play.petGiven()
    let at = TreatDay.timestamp(for: now(), calendar: .current)
    Task { [delivery] in await delivery.play(.pet, at) }
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
      onStatus?(newStatus)
    case .note(let strokes):
      store.send(.noteReceived(strokes))
      keep(strokes, .received)
    case .partnerPetted:
      play.petReceived()
    case .treats(let days):
      applyTreat { $0.treatsReceived(days) }
    }
  }

  private func keep(_ strokes: [Stroke], _ direction: NoteRecord.Direction) {
    let note = NoteRecord(direction: direction, date: now(), strokes: strokes)
    // Shown straight away: a failed save costs the note after a restart, not on screen.
    notes.insert(note, at: 0)
    let previous = lastSave
    lastSave = Task { [archive] in
      await previous?.value
      _ = try? await archive.add(note)
    }
  }
}
