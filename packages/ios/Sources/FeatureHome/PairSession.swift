import BilletKit
import Delivery
import DesignSystem
import FeatureInbox
import Foundation
import Labs
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
  let trips: CatTripController
  /// True when the partner is the scripted one from Labs.
  let isFakePartner: Bool
  /// The lab switches. Each experiment checks its own.
  let labs: WidgetFeaturesModel
  /// The notes hung in frames, for the "framed notes" experiment.
  let frames: FramedNotes
  /// Notes held back until a set time, for the "sealed note" experiment.
  let sealed: SealedBoxStore
  /// The porch light, for the experiment that lets the streak wait.
  let porch: PorchLightStore
  /// The lamp colours, for the experiment that shares how today feels.
  let lamp: LampStore
  /// The day of the next visit, for the suitcase by the door.
  let visit: NextVisitStore
  /// Wrapped gifts on and off the doormat.
  let gifts: GiftBoxStore
  /// The advent calendar's doors.
  let advent: AdventStore
  /// The cat's needs, worked out from what both partners did.
  let life: PetLifeModel
  /// The cat's brain, run from its life.
  let brain: CatBrainModel
  private(set) var status = NoteDelivery.Status.connecting
  /// True once this connection has reached the room, which makes a later `.connecting` a reconnect.
  private(set) var hasConnected = false
  private(set) var notes: [NoteRecord] = []
  private(set) var notesFailedToLoad = false
  private(set) var play: PairPlay {
    didSet {
      if let playStorage, play.saved != oldValue.saved { playStorage.save(play.saved) }
    }
  }
  /// Counts up each time the partner reacts to a note this device sent, and holds that reaction.
  private(set) var reactionsSeen = 0
  private(set) var lastReaction: Reaction?
  /// The cat's trip with the last note this device sent, for the "cat came back" experiment.
  private(set) var catReturn = CatReturn()
  /// Both fingers on the cat, for the "two wisps" experiment.
  private(set) var hold = TogetherHold()
  /// True while the shared treat falls onto the cat.
  private(set) var treatFalling = false

  /// Called on each status change.
  @ObservationIgnored var onStatus: ((NoteDelivery.Status) -> Void)?
  /// Called with each of the partner's moves while the pair chooses its cat. Moves that arrive
  /// before anything listens are kept, the last few, and handed over when something does.
  @ObservationIgnored var onAdoption: ((AdoptionMove) -> Void)? {
    didSet {
      guard let onAdoption else { return }
      let early = earlyAdoption
      earlyAdoption = []
      for move in early { onAdoption(move) }
    }
  }
  @ObservationIgnored private var earlyAdoption: [AdoptionMove] = []

  @ObservationIgnored private let delivery: NoteDelivery
  @ObservationIgnored private let archive: NoteArchive
  @ObservationIgnored private let now: @Sendable () -> Date
  /// Set only where no room keeps the play.
  @ObservationIgnored private let playStorage: PairPlayStorage?
  @ObservationIgnored private var connection: Task<Void, Never>?
  @ObservationIgnored private var lastSave: Task<Void, Never>?

  init(
    room: DemoRoom,
    delivery: NoteDelivery,
    archive: NoteArchive,
    shop: ShopStore,
    now: @escaping @Sendable () -> Date = { .now },
    trips: CatTripController = .live(),
    isFakePartner: Bool = false,
    labs: WidgetFeaturesModel = WidgetFeaturesModel(store: nil),
    playStorage: PairPlayStorage? = nil
  ) {
    self.playStorage = playStorage
    self.isFakePartner = isFakePartner
    self.labs = labs
    frames = FramedNotes(key: isFakePartner ? "labs.framedNotes.fake" : "labs.framedNotes")
    advent = AdventStore(
      year: Calendar.current.component(.year, from: .now),
      key: isFakePartner ? "labs.advent.fake" : "labs.advent")
    gifts = GiftBoxStore(key: isFakePartner ? "labs.giftBox.fake" : "labs.giftBox")
    visit = NextVisitStore(key: isFakePartner ? "labs.nextVisit.fake" : "labs.nextVisit")
    lamp = LampStore(key: isFakePartner ? "labs.lampColour.fake" : "labs.lampColour")
    porch = PorchLightStore(key: isFakePartner ? "labs.porchLight.fake" : "labs.porchLight")
    sealed = SealedBoxStore(key: isFakePartner ? "labs.sealedBox.fake" : "labs.sealedBox")
    life = PetLifeModel(
      me: room.device, fallbackPartner: isFakePartner ? FakePartnerRoom.device : nil,
      key: isFakePartner ? "life.events.fake" : "life.events", clock: now)
    brain = CatBrainModel(life: life)
    self.room = room
    self.delivery = delivery
    self.archive = archive
    self.shop = shop
    renovator = RoomRenovator(store: shop)
    self.now = now
    self.trips = trips
    play = PairPlay(device: room.device, saved: playStorage?.load())
    let porch = porch
    life.frozen = { [labs] in
      guard labs.isOn(LabExperiment.porchLight), let light = porch.light else { return [] }
      return [DateInterval(start: light.from, end: light.ends(calendar: .current))]
    }
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
      frames.prune(keeping: notes)
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
    if labs.isOn(LabExperiment.advent), let door = advent.finishDrawing(strokes) {
      store.send(.canvasClosed)
      Task { [delivery] in await delivery.signal(.adventDoor(number: door, strokes: strokes)) }
      return
    }
    if labs.isOn(LabExperiment.sealedNote), sealed.sealNext {
      sealed.sealNext = false
      let opens = SealedBox.tomorrowMorning(after: now(), calendar: .current)
      sealed.seal(SealedNote(id: id, strokes: strokes, opensAt: opens, direction: .outgoing))
      store.send(.canvasClosed)
      return
    }
    dispatch(strokes, id: id)
  }

  /// Opens the sealed notes whose time has come: this phone's go to the partner, the partner's
  /// are carried in by the cat.
  func openSealedNotes() {
    for note in sealed.release(at: now()) {
      switch note.direction {
      case .outgoing: dispatch(note.strokes, id: note.id)
      case .incoming:
        store.send(.noteReceived(note.strokes))
        keep(note.strokes, .received, id: note.id)
      }
    }
  }

  /// The shared streak on `day`, counting through the nights the porch light covers.
  func streak(today day: String, calendar: Calendar) -> Int {
    let paused =
      labs.isOn(LabExperiment.porchLight) ? porch.covered(now: now(), calendar: calendar) : []
    return play.ledger.streak(today: day, calendar: calendar, paused: paused)
  }

  /// This phone's lamp went out or came back on. The partner is told through `signal`, which the
  /// real room ignores.
  func lampChanged(out: Bool) {
    Task { [delivery] in await delivery.signal(.lamp(on: !out)) }
    if out { lived(.sleep) }
  }

  /// Wraps `item` from the closet for the partner's doormat.
  func wrap(_ item: ShopItem) {
    guard (try? shop.give(item, transaction: shop.newTransaction())) != nil else { return }
    let gift = Gift(itemID: item.id, direction: .outgoing)
    gifts.add(gift)
    Task { [delivery] in await delivery.signal(.gift(id: gift.id, item: item.id)) }
  }

  /// Opens a wrapped gift: the item goes into the closet.
  func unwrapGift(_ id: UUID) {
    guard let itemID = gifts.unwrap(id), let item = shop.catalog.item(itemID) else { return }
    _ = try? shop.receive(item, transaction: "gift-\(id.uuidString)")
    Task { [delivery] in await delivery.signal(.giftOpened(id: id)) }
  }

  /// This phone's finger went down on the cat, or came up.
  func holdChanged(_ holding: Bool) {
    hold.iHold(holding, at: now())
  }

  private func dispatch(_ strokes: [Stroke], id: UUID) {
    // The note carries its own event to the room, under the note's ID.
    life.record(.note, id: id)
    store.send(.drawingSent(strokes, id: id))
    catReturn.sent(id)
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
    lived(.pet)
  }

  /// A game with the cat: it batted at a finger or chased something the user moved.
  func played() {
    lived(.play)
  }

  /// Shoos the cat off the desk or the cardigan; enough of these and it stays off.
  func shooed() {
    lived(.shoo)
  }

  /// Puts the cat to bed, from its thought bubble.
  func tuckIn() {
    lived(.sleep)
  }

  /// The cat ate something other than the day's treat, such as one from the closet.
  func fed() {
    lived(.feed)
  }

  /// Keeps an event of this phone's and tells the room.
  private func lived(_ kind: LifeEvent.Kind) {
    let event = life.record(kind)
    Task { [delivery] in await delivery.life(event) }
  }

  /// Sets the room's light here at once and tells the room, which tells the partner.
  func switchLight(_ light: RoomLight) {
    guard light != play.roomLight else { return }
    play.light(light)
    Task { [delivery] in await delivery.switchLight(light) }
  }

  /// Names the cat here at once and tells the room. If the partner named it first, the room's
  /// name replaces this one.
  func nameCat(_ raw: String) {
    guard let name = CatName.clean(raw) else { return }
    play.named(name)
    Task { [delivery] in await delivery.nameCat(name) }
  }

  /// Names the cat here at once and tells the room, over any name it had: the last name given
  /// wins on both phones.
  func renameCat(_ raw: String) {
    guard let name = CatName.clean(raw) else { return }
    play.named(name)
    Task { [delivery] in await delivery.renameCat(name) }
  }

  /// Tells the partner this phone's move while the pair chooses its cat.
  func adopt(_ move: AdoptionMove) {
    Task { [delivery] in await delivery.adopt(move) }
  }

  /// What became of an action taken outside the app.
  enum Disposition: Equatable {
    case done
    /// It cannot be carried out yet, so it stays queued.
    case keep
    /// It is no longer meaningful, so it is dropped without being sent.
    case drop
  }

  private var isConnected: Bool {
    switch status {
    case .partnerAway, .partnerHere: true
    case .connecting, .refused: false
    }
  }

  /// Carries out one action from a widget, control or Live Activity through the same paths a tap
  /// in the app takes. Anything that must reach the partner waits until the room is connected.
  func perform(_ action: WidgetAction, now: Date, calendar: Calendar = .current) -> Disposition {
    switch action.kind {
    case .openCanvas:
      store.send(.canvasOpened)
      return .done
    case .pet:
      guard isConnected else { return .keep }
      pet()
      return .done
    case .treat:
      let today = TreatDay.key(for: now, calendar: calendar)
      guard action.day == today else { return .drop }
      switch play.status(on: today) {
      case .waitingOnPartner, .fed: return .drop
      case .neither, .waitingOnMe: break
      }
      guard isConnected else { return .keep }
      giveTreat(on: today)
      return .done
    case .heart:
      guard let id = action.note else { return .drop }
      guard isConnected, let note = notes.first(where: { $0.id == id }) else { return .keep }
      react(to: note, .heart)
      return .done
    }
  }

  /// Carries out what the queue holds and removes what was handled. Returns true when it opened
  /// the canvas.
  @discardableResult
  func drain(_ queue: ActionQueue, now: Date = .now) -> Bool {
    var openedCanvas = false
    for action in queue.pending(at: now) {
      switch perform(action, now: now) {
      case .done:
        openedCanvas = openedCanvas || action.kind == .openCanvas
        queue.remove(action)
      case .drop:
        queue.remove(action)
      case .keep:
        break
      }
    }
    return openedCanvas
  }

  func giveTreat(on day: String) {
    applyTreat { _ = $0.treatGiven(on: day) }
    let at = TreatDay.timestamp(for: now(), calendar: .current)
    Task { [delivery] in await delivery.play(.treat, at) }
    fed()
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
    case .sealedNote(let strokes, let id, let opensAt):
      sealed.seal(SealedNote(id: id, strokes: strokes, opensAt: opensAt, direction: .incoming))
    case .adventDoor(let number, let strokes):
      advent.partnerFilled(number, strokes: strokes)
    case .gift(let id, let item):
      gifts.add(Gift(id: id, itemID: item, direction: .incoming))
    case .giftOpened(let id):
      gifts.partnerOpened(id)
    case .partnerGlow(let glow):
      lamp.partnerGlows(glow)
    case .partnerHolding(let holding):
      hold.partnerHolds(holding, at: now())
    case .noteOpened(let id):
      catReturn.opened(id, at: now())
    case .partnerPetted:
      play.petReceived()
    case .life(let events):
      life.receive(events)
    case .treats(let days):
      applyTreat { $0.treatsReceived(days) }
    case .catName(let name):
      play.named(name)
    case .roomLight(let light):
      play.light(light)
    case .partnerAdoption(let move):
      if let onAdoption {
        onAdoption(move)
      } else {
        earlyAdoption = Array((earlyAdoption + [move]).suffix(8))
      }
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
