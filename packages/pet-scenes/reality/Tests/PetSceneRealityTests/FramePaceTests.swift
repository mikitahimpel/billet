import Foundation
import Testing

@testable import PetSceneReality

@MainActor @Suite struct FramePaceTests {
  @Test func onlySeriousOrCriticalHeatCounts() {
    #expect(!FramePace.isHot(.nominal))
    #expect(!FramePace.isHot(.fair))
    #expect(FramePace.isHot(.serious))
    #expect(FramePace.isHot(.critical))
  }

  @Test func aStillRoomDrawsLessThanAMovingOne() {
    let pace = FramePace.shared
    guard !pace.isHot else { return }
    #expect(pace.rate(isStill: false) == FramePace.moving)
    #expect(pace.rate(isStill: true) == FramePace.still)
    #expect(FramePace.still < FramePace.moving)
    #expect(FramePace.hot < FramePace.moving)
  }

  @Test func uncappedDrawsAtTheDisplaysRate() {
    let pace = FramePace.shared
    pace.setCapped(false)
    defer { pace.setCapped(true) }
    #expect(pace.rate(isStill: true) == nil)
    #expect(RoomLayerSchedule.busy == 1 / 60)
  }
}
