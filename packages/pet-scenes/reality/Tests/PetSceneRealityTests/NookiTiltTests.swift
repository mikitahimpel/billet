import RealityKit
import Testing
import simd

@testable import PetSceneReality

@Suite struct NookiTiltTests {
  private static let held = SIMD3<Float>(0, -0.7, -0.7)
  private static let step: Float = 1.0 / 60

  private func following(
    _ tilt: inout NookiTilt, _ gravity: SIMD3<Float>, seconds: Float
  ) {
    for _ in 0..<Int(seconds / Self.step) { tilt.update(gravity: gravity, delta: Self.step) }
  }

  @Test func theFirstReadingIsLevelHoweverThePhoneIsHeld() {
    var tilt = NookiTilt()
    tilt.update(gravity: [0.4, -0.5, -0.7], delta: Self.step)
    #expect(tilt.lean == .zero)
  }

  @Test func leaningThePhoneSwingsTheViewThatWay() {
    var tilt = NookiTilt()
    tilt.update(gravity: Self.held, delta: Self.step)
    following(&tilt, Self.held + [0.1, 0, 0], seconds: 0.5)
    #expect(tilt.lean.x > 0.03)
    #expect(abs(tilt.lean.y) < 0.001)
  }

  @Test func aHeldPoseFadesBackToLevel() {
    var tilt = NookiTilt()
    tilt.update(gravity: Self.held, delta: Self.step)
    following(&tilt, Self.held + [0.2, 0, 0], seconds: 40)
    #expect(abs(tilt.lean.x) < 0.01)
  }

  @Test func theSwingNeverPassesItsReach() {
    var tilt = NookiTilt()
    tilt.update(gravity: Self.held, delta: Self.step)
    following(&tilt, [1, 0, 0], seconds: 1)
    #expect(tilt.lean.x <= NookiTilt.reach)
    #expect(tilt.lean.x > NookiTilt.reach * 0.8)
  }

  @Test func sensorNoiseMovesNothing() {
    var tilt = NookiTilt()
    tilt.update(gravity: Self.held, delta: Self.step)
    for index in 0..<120 {
      let noise: Float = index.isMultiple(of: 2) ? 0.006 : -0.006
      tilt.update(gravity: Self.held + [noise, 0, noise], delta: Self.step)
    }
    #expect(tilt.lean == .zero)
    #expect(!tilt.isMoving)
  }

  @Test func withNoReadingItEasesBackToLevelAndRests() {
    var tilt = NookiTilt()
    tilt.update(gravity: Self.held, delta: Self.step)
    following(&tilt, Self.held + [0.2, 0.2, 0], seconds: 1)
    for _ in 0..<600 { tilt.settle(delta: Self.step) }
    #expect(tilt.lean == .zero)
    #expect(!tilt.isMoving)
  }

  @MainActor @Test func theScriptReadsTwoNumbers() {
    #expect(ScriptedTiltSource.parsed("0.1 -0.2\n") == [0.1, -0.7, -0.9])
    #expect(ScriptedTiltSource.parsed("nonsense") == nil)
  }

  @MainActor @Test func theSweepRunsOnlyWhileStarted() {
    var time = 0.0
    let source = ScriptedTiltSource(script: .sweep, now: { time })
    #expect(source.gravity == nil)
    source.start()
    time = 1
    #expect(source.gravity != nil)
    source.stop()
    #expect(source.gravity == nil)
  }

  @MainActor @Test func tiltStopsOffScreenAndUnderReduceMotion() async {
    let source = CountingTiltSource()
    let diorama = NookiDiorama(tiltSource: source)
    diorama.startLoading()
    await diorama.loading?.value
    #expect(source.isRunning)
    diorama.setOnScreen(false)
    #expect(!source.isRunning)
    diorama.setOnScreen(true)
    #expect(source.isRunning)
    diorama.setReduceMotion(true)
    #expect(!source.isRunning)
    diorama.setOnScreen(false)
    diorama.setOnScreen(true)
    #expect(!source.isRunning)
    diorama.setReduceMotion(false)
    #expect(source.isRunning)
  }

  @MainActor @Test func tiltDoesNotStartBeforeTheRoomIsThere() {
    let source = CountingTiltSource()
    let diorama = NookiDiorama(tiltSource: source)
    diorama.setOnScreen(true)
    #expect(!source.isRunning)
  }
}

@MainActor private final class CountingTiltSource: NookiTiltSource {
  var gravity: SIMD3<Float>?
  var isRunning = false
  func start() { isRunning = true }
  func stop() { isRunning = false }
}
