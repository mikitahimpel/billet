import Foundation
import Pet
import Testing

@testable import WidgetBridge

@Suite struct ActionTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func snapshot(
    treat: WidgetSnapshot.Treat = .neither, note: UUID? = UUID()
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      treat: treat, treatDay: TreatDay.key(for: now, calendar: calendar),
      latestReceivedNote: note, updatedAt: now)
  }

  private func decide(
    _ kind: WidgetActionKind, _ surface: ActionSurface = .home,
    features: WidgetFeatures = WidgetFeatures(), snapshot: WidgetSnapshot? = nil,
    pending: [WidgetAction] = []
  ) -> Result<WidgetAction, WidgetActionRequest.Refusal> {
    WidgetActionRequest.decide(
      kind, at: surface, features: features, snapshot: snapshot ?? self.snapshot(),
      pending: pending, now: now, calendar: calendar)
  }

  @Test(arguments: [
    (WidgetActionKind.treat, WidgetFeature.buttonTreat),
    (.pet, .buttonPet),
    (.heart, .buttonHeart),
  ])
  func eachButtonChecksItsOwnFlag(_ kind: WidgetActionKind, _ flag: WidgetFeature) {
    #expect((try? decide(kind).get()) != nil)
    var features = WidgetFeatures()
    features.set(flag, on: false)
    #expect(decide(kind, features: features) == .failure(.off))
    for other in [WidgetFeature.buttonTreat, .buttonPet, .buttonHeart] where other != flag {
      var one = WidgetFeatures()
      one.set(other, on: false)
      #expect((try? decide(kind, features: one).get()) != nil)
    }
  }

  @Test func lockScreenNeedsItsOwnFlagToo() {
    var features = WidgetFeatures()
    features.set(.lockScreenButtons, on: false)
    #expect(decide(.pet, .lockScreen, features: features) == .failure(.off))
    #expect((try? decide(.pet, .home, features: features).get()) != nil)
    features.set(.lockScreenButtons, on: true)
    features.set(.buttonPet, on: false)
    #expect(decide(.pet, .lockScreen, features: features) == .failure(.off))
  }

  @Test func aTreatAlreadyGivenOrWaitingIsNotQueuedTwice() {
    #expect(decide(.treat, snapshot: snapshot(treat: .waitingOnPartner)) == .failure(.duplicate))
    #expect(decide(.treat, snapshot: snapshot(treat: .fed)) == .failure(.duplicate))
    #expect((try? decide(.treat, snapshot: snapshot(treat: .waitingOnMe)).get()) != nil)
    let first = try? decide(.treat).get()
    #expect(first?.day == TreatDay.key(for: now, calendar: calendar))
    #expect(decide(.treat, pending: first.map { [$0] } ?? []) == .failure(.duplicate))
  }

  @Test func petsPileUpOnlyToTheLimit() {
    let pets = (0..<WidgetActionRequest.petLimit).map {
      WidgetAction(kind: .pet, at: now.addingTimeInterval(Double($0)), day: "d")
    }
    #expect(decide(.pet, pending: Array(pets.dropLast())).isSuccess)
    #expect(decide(.pet, pending: pets) == .failure(.duplicate))
  }

  @Test func aHeartNeedsANoteAndAnswersItOnce() {
    #expect(decide(.heart, snapshot: snapshot(note: nil)) == .failure(.noNote))
    let note = UUID()
    let action = try? decide(.heart, snapshot: snapshot(note: note)).get()
    #expect(action?.note == note)
    #expect(
      decide(.heart, snapshot: snapshot(note: note), pending: action.map { [$0] } ?? [])
        == .failure(.duplicate))
  }

  @Test(arguments: [
    (WidgetActionKind.pet, WidgetFeature.controlPet),
    (.heart, .controlHeart),
    (.openCanvas, .controlCanvas),
  ])
  func eachControlChecksItsOwnFlag(_ kind: WidgetActionKind, _ flag: WidgetFeature) {
    #expect(decide(kind, .control).isSuccess)
    var features = WidgetFeatures()
    features.set(flag, on: false)
    #expect(decide(kind, .control, features: features) == .failure(.off))
    // The button flags on the Home Screen do not switch the controls.
    var buttons = WidgetFeatures()
    for button in [WidgetFeature.buttonPet, .buttonHeart, .buttonTreat] {
      buttons.set(button, on: false)
    }
    #expect(decide(kind, .control, features: buttons).isSuccess)
  }

  @Test func openingTheCanvasFromAButtonSurfaceNeedsNoFlag() {
    #expect(decide(.openCanvas, .home).isSuccess)
  }

  @Test func queueKeepsOrderRemovesAndDropsStale() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let queue = ActionQueue(directory: directory)
    let old = WidgetAction(kind: .pet, at: now.addingTimeInterval(-3600), day: "d")
    let second = WidgetAction(kind: .treat, at: now.addingTimeInterval(-20), day: "d")
    let first = WidgetAction(kind: .heart, at: now.addingTimeInterval(-30), day: "d", note: UUID())
    for action in [second, old, first] { try queue.enqueue(action) }
    #expect(queue.pending(at: now) == [first, second])
    queue.remove(first)
    #expect(queue.pending(at: now) == [second])
    queue.removeAll()
    #expect(queue.pending(at: now).isEmpty)
  }

  @Test func eachKindExpiresOnItsOwnClock() {
    let at = now.addingTimeInterval(-11 * 60)
    #expect(WidgetAction(kind: .pet, at: at, day: "d").isStale(at: now))
    #expect(WidgetAction(kind: .openCanvas, at: at, day: "d").isStale(at: now))
    #expect(!WidgetAction(kind: .treat, at: at, day: "d").isStale(at: now))
    #expect(!WidgetAction(kind: .heart, at: at, day: "d").isStale(at: now))
  }
}

extension Result {
  fileprivate var isSuccess: Bool {
    if case .success = self { true } else { false }
  }
}

@Suite struct ActionButtonStateTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func snapshot(_ treat: WidgetSnapshot.Treat, note: UUID?) -> WidgetSnapshot {
    WidgetSnapshot(
      treat: treat, treatDay: TreatDay.key(for: now, calendar: calendar), latestReceivedNote: note,
      updatedAt: now)
  }

  private func state(
    _ kind: WidgetActionKind, _ snapshot: WidgetSnapshot?, pending: [WidgetAction] = []
  ) -> ActionButtonState {
    .make(kind, snapshot: snapshot, pending: pending, now: now, calendar: calendar)
  }

  @Test func treatReflectsTheDayAndTheQueue() {
    #expect(state(.treat, snapshot(.neither, note: nil)).isEnabled)
    #expect(state(.treat, snapshot(.waitingOnMe, note: nil)).isEnabled)
    #expect(state(.treat, snapshot(.waitingOnPartner, note: nil)).title == "Given")
    #expect(!state(.treat, snapshot(.fed, note: nil)).isEnabled)
    let queued = [WidgetAction(kind: .treat, at: now, day: "d")]
    #expect(state(.treat, snapshot(.neither, note: nil), pending: queued).title == "Queued")
  }

  @Test func heartNeedsANote() {
    #expect(!state(.heart, snapshot(.neither, note: nil)).isEnabled)
    #expect(!state(.heart, nil).isEnabled)
    #expect(state(.heart, snapshot(.neither, note: UUID())).isEnabled)
  }

  @Test func petStaysPressableWhileOthersWait() {
    let queued = [WidgetAction(kind: .pet, at: now, day: "d")]
    #expect(state(.pet, nil, pending: queued).isEnabled)
    #expect(state(.pet, nil, pending: queued).title == "Queued")
  }

  @Test func buttonsShownFollowFlagsAndSurface() {
    var features = WidgetFeatures()
    #expect(ActionButtonState.kinds(features: features, surface: .home) == [.treat, .pet, .heart])
    features.set(.buttonPet, on: false)
    #expect(ActionButtonState.kinds(features: features, surface: .home) == [.treat, .heart])
    features.set(.lockScreenButtons, on: false)
    #expect(ActionButtonState.kinds(features: features, surface: .lockScreen).isEmpty)
  }
}
