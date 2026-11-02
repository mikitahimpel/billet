import Testing

@testable import PetScene

@Suite struct FlyInTimelineTests {
  @Test func theCameraStartsFarOutAndArrivesHome() {
    let start = FlyInTimeline.offset(at: 0)
    #expect(start.yaw > 0.5 && start.pitch > 0.15 && start.distance > 2)
    let end = FlyInTimeline.offset(at: FlyInTimeline.flight.upperBound)
    #expect(end.yaw == 0 && end.pitch == 0 && end.distance == 1)
  }

  @Test func theFlightIsBetweenOneAndAHalfAndTwoAndAHalfSeconds() {
    let length = FlyInTimeline.flight.upperBound - FlyInTimeline.flight.lowerBound
    #expect((1.5...2.5).contains(length))
  }

  @Test func theFlightNeverGoesBack() {
    var last = FlyInTimeline.offset(at: 0).distance
    for step in 1...100 {
      let distance = FlyInTimeline.offset(at: Double(step) * 0.025).distance
      #expect(distance <= last)
      last = distance
    }
  }

  @Test func theOpeningHappensInOrder() {
    #expect(FlyInTimeline.lights(at: 0) == 0)
    #expect(FlyInTimeline.lights(at: FlyInTimeline.wake) > 0.9)
    #expect(FlyInTimeline.wake < FlyInTimeline.look)
    #expect(FlyInTimeline.note(at: FlyInTimeline.look) == 0)
    #expect(FlyInTimeline.note(at: FlyInTimeline.length) == 1)
  }
}
