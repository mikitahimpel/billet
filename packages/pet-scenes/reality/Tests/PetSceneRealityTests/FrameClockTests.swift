import Foundation
import Testing

@testable import PetSceneReality

@MainActor
struct FrameClockTests {
  @Test func stepsOnceAFrameWithTheTimeBetweenFrames() {
    let clock = FrameClock()
    var steps: [TimeInterval] = []
    clock.run { steps.append($0) }
    clock.isPaused = true
    clock.isPaused = false
    clock.fire(at: 10)
    clock.fire(at: 10.02)
    clock.fire(at: 10.05)
    clock.stop()
    #expect(steps.count == 3)
    #expect(abs(steps[0] - 1 / FrameClock.framesPerSecond) < 1e-9)
    #expect(abs(steps[1] - 0.02) < 1e-9)
    #expect(abs(steps[2] - 0.03) < 1e-9)
  }

  @Test func aStallIsNotThrownForwardAtOnce() {
    let clock = FrameClock()
    var steps: [TimeInterval] = []
    clock.run { steps.append($0) }
    clock.fire(at: 1)
    clock.fire(at: 4)
    clock.stop()
    #expect(steps.last == FrameClock.longestStep)
  }

  @Test func timePausedDoesNotCount() {
    let clock = FrameClock()
    var steps: [TimeInterval] = []
    clock.run { steps.append($0) }
    clock.fire(at: 1)
    clock.isPaused = true
    clock.fire(at: 1.5)
    clock.isPaused = false
    clock.fire(at: 9)
    clock.stop()
    #expect(steps.count == 2)
    #expect(abs(steps[1] - 1 / FrameClock.framesPerSecond) < 1e-9)
  }

  @Test func aStoppedClockStepsNothing() {
    let clock = FrameClock()
    var steps = 0
    clock.run { _ in steps += 1 }
    clock.stop()
    clock.fire(at: 1)
    #expect(steps == 0)
    #expect(!clock.isRunning)
  }
}
