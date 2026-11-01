import Foundation
import Testing
import WidgetBridge

@testable import FeatureHome

@MainActor
private final class Recorder {
  var started: [(String?, CatTrip.Content)] = []
  var ended: [(CatTrip.Content, TimeInterval)] = []

  var backend: CatTripController.Backend {
    .init(
      start: { name, content in self.started.append((name, content)) },
      update: { _ in },
      end: { content, lingering in self.ended.append((content, lingering)) })
  }
}

@MainActor
@Suite struct CatTripControllerTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func controller(
    _ recorder: Recorder, features: WidgetFeatures = WidgetFeatures()
  ) -> CatTripController {
    CatTripController(backend: recorder.backend, features: { features })
  }

  @Test func aNoteSettingOffStartsATripAndHangingEndsIt() async {
    let recorder = Recorder()
    let trips = controller(recorder)
    await trips.noteOnItsWay(catName: "Mochi", reveal: .seconds(3), now: now)
    #expect(recorder.started.count == 1)
    #expect(recorder.started.first?.0 == "Mochi")
    #expect(recorder.started.first?.1.phase == .onItsWay)
    #expect(recorder.started.first?.1.arrivesAt == now.addingTimeInterval(7))
    await trips.noteHung(now: now.addingTimeInterval(5))
    let ended = recorder.ended.first
    #expect(ended?.0.phase == .hung)
    #expect(ended?.0.arrivesAt == now.addingTimeInterval(5))
    #expect(ended?.1 == CatTrip.lingerAfterHung)
    #expect(trips.current == nil)
  }

  @Test func withTheFeatureOffNothingStarts() async {
    var features = WidgetFeatures()
    features.set(.liveActivity, on: false)
    let recorder = Recorder()
    let trips = controller(recorder, features: features)
    await trips.noteOnItsWay(catName: nil, reveal: .seconds(3), now: now)
    await trips.noteHung(now: now)
    #expect(recorder.started.isEmpty)
    #expect(recorder.ended.isEmpty)
  }

  @Test func aSecondNoteEndsTheTripStillRunning() async {
    let recorder = Recorder()
    let trips = controller(recorder)
    await trips.noteOnItsWay(catName: nil, reveal: .seconds(3), now: now)
    await trips.noteOnItsWay(catName: nil, reveal: .seconds(3), now: now.addingTimeInterval(2))
    #expect(recorder.started.count == 2)
    #expect(recorder.ended.count == 1)
    #expect(recorder.ended.first?.1 == 0)
  }

  @Test func hangingWithoutATripDoesNothing() async {
    let recorder = Recorder()
    await controller(recorder).noteHung(now: now)
    #expect(recorder.ended.isEmpty)
  }

  @Test func cancellingEndsAtOnce() async {
    let recorder = Recorder()
    let trips = controller(recorder)
    await trips.noteOnItsWay(catName: nil, reveal: .seconds(3), now: now)
    await trips.cancel()
    #expect(recorder.ended.first?.1 == 0)
    #expect(trips.current == nil)
  }
}
