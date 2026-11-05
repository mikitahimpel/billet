import Testing

@testable import PetScene

@Suite struct FlyInTimelineTests {
  @Test func theCameraStartsFarOutAndArrivesHome() {
    let start = FlyInTimeline.offset(at: 0)
    #expect(start.yaw > 0.2 && start.pitch > 0.1 && start.distance > 1.5)
    let end = FlyInTimeline.offset(at: FlyInTimeline.flight.upperBound)
    #expect(end.yaw == 0 && end.pitch == 0 && end.distance == 1)
  }

  @Test func theWholeOpeningIsBetweenOneAndAHalfAndTwoSeconds() {
    let length = FlyInTimeline.flight.upperBound - FlyInTimeline.flight.lowerBound
    #expect((1.5...2).contains(length))
    #expect((1.5...2).contains(FlyInTimeline.length))
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
    // The lights are up by the time the cat looks up, and the note grows in after.
    #expect(FlyInTimeline.lights(at: FlyInTimeline.look) == 1)
    #expect(FlyInTimeline.note(at: FlyInTimeline.look) == 0)
    #expect(FlyInTimeline.note(at: FlyInTimeline.length) == 1)
  }
}
