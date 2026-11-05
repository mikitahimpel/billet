import Foundation
import Testing
import simd

@testable import Pet

@Suite("CatPursuit")
struct CatPursuitTests {
  /// Runs `pursuit` at 60 frames a second for `seconds`, with the toy where `toy` says at each
  /// time, and returns what happened.
  private func run(
    _ pursuit: inout CatPursuit, from start: Double = 0, for seconds: Double,
    toy: (Double) -> (SIMD2<Float>?, Float)
  ) -> (events: [CatPursuit.Event], phases: [CatPursuit.Phase]) {
    var events: [CatPursuit.Event] = []
    var phases: [CatPursuit.Phase] = [pursuit.phase]
    var t = start
    while t < start + seconds {
      t += 1.0 / 60
      let (target, speed) = toy(t)
      if let event = pursuit.step(target: target, targetSpeed: speed, at: t, delta: 1.0 / 60) {
        events.append(event)
      }
      if phases.last != pursuit.phase { phases.append(pursuit.phase) }
    }
    return (events, phases)
  }

  @Test func stalksWigglesAndPouncesOnAFeather() {
    var pursuit = CatPursuit(toy: .wand, from: [0, 0], heading: 0, length: 1, at: 0)
    // A feather twitching on the spot a few lengths ahead.
    let result = run(&pursuit, for: 8) { t in ([Float(sin(t * 8)) * 0.05, -3], 0.4) }
    #expect(result.events.contains(.caught))
    #expect(Array(result.phases.prefix(5)) == [.watch, .stalk, .wiggle, .pounce, .caught])
    #expect(pursuit.catches >= 1)
  }

  @Test func losesInterestInAToyLeftLying() {
    var pursuit = CatPursuit(toy: .wand, from: [0, 0], heading: 0, length: 1, at: 0)
    let result = run(&pursuit, for: 12) { _ in ([0, -8], 0) }
    #expect(pursuit.isDone)
    #expect(!result.events.contains(.caught))
  }

  @Test func runsAfterAFleeingDot() {
    var pursuit = CatPursuit(toy: .laser, from: [0, 0], heading: 0, length: 1, at: 0)
    _ = run(&pursuit, for: 0.7) { t in ([0, -4 - Float(t)], 3) }
    var fastest: Float = 0
    for frame in 1...30 {
      let t = 0.7 + Double(frame) / 60
      _ = pursuit.step(target: [0, -4 - Float(t)], targetSpeed: 3, at: t, delta: 1.0 / 60)
      fastest = max(fastest, pursuit.pose.speed)
    }
    #expect(fastest > 1.5)
  }

  @Test func bringsABallBackAndDropsIt() {
    let thrower = SIMD2<Float>(0, 1)
    var pursuit = CatPursuit(
      toy: .ball, from: [0, 0], heading: 0, length: 1, fetchTo: thrower, at: 0)
    let result = run(&pursuit, for: 14) { _ in ([0, -2.5], 0.3) }
    #expect(result.events.first == .caught)
    #expect(result.phases.contains(.carry))
    guard case .dropped(let at) = result.events.last else {
      Issue.record("never dropped the ball")
      return
    }
    #expect(simd_distance(at, thrower) < 0.1)
  }

  @Test func givesUpWhenTheToyIsGone() {
    var pursuit = CatPursuit(toy: .yarn, from: [0, 0], heading: 0, length: 1, at: 0)
    _ = pursuit.step(target: nil, targetSpeed: 0, at: 0.1, delta: 0.1)
    #expect(pursuit.isDone)
  }
}

@Suite("RollingToy")
struct RollingToyTests {
  @Test func slowsAndStaysInside() {
    var ball = RollingToy(at: [0, 0], bounds: ([-1, -1], [1, 1]), grip: 0.3)
    ball.velocity = [4, 0]
    for _ in 0..<600 { ball.step(1.0 / 60) }
    #expect(ball.speed == 0)
    #expect(abs(ball.position.x) <= 1)
    #expect(abs(ball.position.y) <= 1)
  }
}
