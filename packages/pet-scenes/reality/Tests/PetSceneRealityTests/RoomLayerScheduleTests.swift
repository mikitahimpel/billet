import Foundation
import Testing

@testable import PetSceneReality

@Suite struct RoomLayerScheduleTests {
  /// Settled ticks of a slower layer fall on ticks of a faster one, wherever each started.
  @Test func settledLayersTickTogether() {
    let busyUntil = Date(timeIntervalSinceReferenceDate: 1000)
    func ticks(startingAt start: TimeInterval, every interval: TimeInterval) -> [TimeInterval] {
      let schedule = RoomLayerSchedule(busyUntil: busyUntil, steady: interval, isPaused: false)
      let entries = schedule.entries(
        from: Date(timeIntervalSinceReferenceDate: start), mode: .normal)
      return entries.prefix(40).map(\.timeIntervalSinceReferenceDate).filter { $0 > 1000.1 }
    }
    let fast = ticks(startingAt: 999.993, every: 1 / 30)
    let slow = ticks(startingAt: 999.611, every: 1 / 15)
    #expect(!slow.isEmpty)
    for tick in slow {
      #expect(fast.contains { abs($0 - tick) < 1e-6 } || tick > fast.last!)
    }
  }

  @Test func aTickIsAlwaysLater() {
    let onTick = Date(timeIntervalSinceReferenceDate: 30)
    let next = RoomLayerSchedule.tick(after: onTick, every: 1 / 15)
    #expect(abs(next.timeIntervalSince(onTick) - 1 / 15) < 1e-6)
    let between = Date(timeIntervalSinceReferenceDate: 30.01)
    #expect(RoomLayerSchedule.tick(after: between, every: 1 / 15) > between)
  }
}
