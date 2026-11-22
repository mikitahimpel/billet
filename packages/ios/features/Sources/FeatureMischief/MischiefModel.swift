import BilletKit
import Foundation
import MischiefInterface
import Observation
import Wire

/// Hide and seek with the toy mouse, for one phone: the pair's hides and finds, the hunt this phone is on and the hide
/// it is choosing. State changes only through the two machines; this runs what they ask for.
@MainActor
@Observable
public final class MischiefModel {
  public struct Pair: Equatable, Sendable {
    public let me: String
    public let partner: String

    public init(me: String, partner: String) {
      self.me = me
      self.partner = partner
    }
  }

  /// What the phone hears of the pair's play, for counting.
  public enum Played: Equatable, Sendable {
    case hid
    case found
  }

  /// Where the ledger is kept between launches.
  public struct Storage {
    public var load: () -> MischiefLedger?
    public var save: (MischiefLedger) -> Void

    public init(load: @escaping () -> MischiefLedger?, save: @escaping (MischiefLedger) -> Void) {
      self.load = load
      self.save = save
    }

    public static var none: Storage { Storage(load: { nil }, save: { _ in }) }
  }

  public private(set) var ledger: MischiefLedger
  public private(set) var hunt: MischiefHuntMachine.State = .idle
  public private(set) var hiding: MischiefHideMachine.State = .closed
  /// Where the room says her spots are; the room tells it again whenever a piece changes them.
  public private(set) var spotMap = MischiefSpotMap()

  @ObservationIgnored private let pair: () -> Pair?
  @ObservationIgnored private let storage: Storage
  @ObservationIgnored private let now: () -> Date
  /// Sends events to the journal and returns the id each went under, nil where one could not be made.
  @ObservationIgnored private let record: ([CatEvent]) -> [IdempotencyKey?]
  /// Where the cat's hints go: the room, once there is one.
  @ObservationIgnored public var hint: (MischiefHint) -> Void
  @ObservationIgnored public var played: (Played) -> Void

  public init(
    pair: @escaping () -> Pair?, storage: Storage = .none, now: @escaping () -> Date = { .now },
    record: @escaping ([CatEvent]) -> [IdempotencyKey?],
    hint: @escaping (MischiefHint) -> Void = { _ in },
    played: @escaping (Played) -> Void = { _ in }
  ) {
    self.pair = pair
    self.storage = storage
    self.now = now
    self.record = record
    self.hint = hint
    self.played = played
    ledger = storage.load() ?? MischiefLedger()
  }

  // MARK: - What the screens read

  /// The mouse the partner hid for this phone's user, still to find.
  public var theirs: MischiefHide? {
    pair().flatMap { ledger.open(hiddenBy: $0.partner, now: now()) }
  }

  /// The mouse this phone's user hid, still hidden.
  public var mine: MischiefHide? {
    pair().flatMap { ledger.open(hiddenBy: $0.me, now: now()) }
  }

  /// The latest finished hides, both ways.
  public var over: [(hide: MischiefHide, status: MischiefStatus)] {
    ledger.over(now: now())
  }

  /// Whether a hide was this phone's user's.
  public func isMine(_ hide: MischiefHide) -> Bool { pair()?.me == hide.by }

  /// The spots to hide at, or to look at while hunting `target`: the room's, plus the one the mouse is at if a piece
  /// has since gone.
  public func spots(including target: MischiefSpot? = nil) -> [MischiefSpot] {
    var spots = spotMap.spots
    if let target, !spots.contains(target) { spots.append(target) }
    return spots
  }

  public var isHunting: Bool {
    switch hunt {
    case .hunting, .found: true
    case .idle: false
    }
  }

  // MARK: - Events in

  public func roomSpots(_ map: MischiefSpotMap) {
    guard map != spotMap else { return }
    spotMap = map
  }

  /// One entry of the pair's journal, the partner's or this phone's own coming back.
  public func receive(_ entry: CatEntry) {
    guard ledger.apply(entry, now: now()) else { return }
    storage.save(ledger)
    if case .hunting(let current) = hunt, ledger.status(of: current.hide, now: now()) != .hidden {
      send(.hideEnded(current.hide.id))
    }
  }

  /// A different pair, or none: what was hidden belonged to the other.
  public func forget() {
    ledger = MischiefLedger()
    hunt = .idle
    hiding = .closed
    storage.save(ledger)
  }

  public func beginHunt() {
    guard let hide = theirs else { return }
    send(.begin(hide, at: now()))
  }

  /// Looks at `spot` for the mouse of the hunt under way.
  public func look(at spot: MischiefSpot) {
    guard case .hunting(let current) = hunt else { return }
    send(.look(spot, warmth: spotMap.warmth(guess: spot, target: current.hide.spot), at: now()))
  }

  public func send(_ event: MischiefHuntMachine.Event) {
    let (next, outputs) = MischiefHuntMachine.transition(hunt, event)
    hunt = next
    for output in outputs {
      switch output {
      case .hint(let value): hint(value)
      case .report(let found): report(found)
      }
    }
  }

  public func send(_ event: MischiefHideMachine.Event) {
    let (next, outputs) = MischiefHideMachine.transition(hiding, event)
    hiding = next
    for output in outputs {
      switch output {
      case .hide(let spot, let line): hide(spot, line: line)
      }
    }
  }

  // MARK: - Outputs

  private func hide(_ spot: MischiefSpot, line: String?) {
    let event = CatEvent.mouseHidden(spot: spot.rawValue, line: line)
    take(event)
    played(.hid)
  }

  private func report(_ found: MischiefHuntMachine.Found) {
    let event = CatEvent.mouseFound(
      hidden: IdempotencyKey(found.hide.id), spot: found.hide.spot.rawValue, tries: found.tries,
      seconds: found.seconds)
    take(event)
    played(.found)
  }

  /// Sends one event to the room and counts it here at once, so the screens do not wait for the journal to come back.
  private func take(_ event: CatEvent) {
    guard let pair = pair(), let id = record([event]).first ?? nil else { return }
    let at = Int(now().timeIntervalSince1970 * 1000)
    let entry = CatEntry(seq: 0, id: id, by: UserId(pair.me), at: at, event: event)
    if ledger.apply(entry, now: now()) { storage.save(ledger) }
  }
}
