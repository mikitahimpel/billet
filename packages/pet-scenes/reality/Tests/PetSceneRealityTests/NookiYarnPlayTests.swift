import Foundation
import Testing
import simd

@testable import PetSceneReality

@Suite struct NookiYarnPlayTests {
  private static let bed: SIMD3<Float> = [0.05, 0.095, 0.12]
  private static let step = 1.0 / 60
  private static let far = SIMD2<Float>(0.5, 0.5)

  private func newPlay() -> NookiYarnPlay {
    NookiYarnPlay(bed: Self.bed, floor: 0.012, restHeading: 3.8)
  }

  private func run(
    _ play: inout NookiYarnPlay, seconds: Double, ball: SIMD2<Float> = far, speed: Float = 0,
    canPlay: Bool = true, reduceMotion: Bool = false
  ) {
    for _ in 0..<Int(seconds / Self.step) {
      play.step(
        ball: .init(position: ball, speed: speed), delta: Self.step, canPlay: canPlay,
        reduceMotion: reduceMotion)
    }
  }

  private func phases(
    _ play: inout NookiYarnPlay, seconds: Double
  ) -> [NookiYarnPlay.Phase] {
    var seen: [NookiYarnPlay.Phase] = []
    for _ in 0..<Int(seconds / Self.step) {
      run(&play, seconds: Self.step)
      if seen.last != play.phase { seen.append(play.phase) }
    }
    return seen
  }

  @Test func aStillBallLeavesMochiAsleep() {
    var play = newPlay()
    run(&play, seconds: 5)
    #expect(play.phase == .resting)
    #expect(!play.pose.frame.eyesOpen)
  }

  @Test func aMovingBallWakesASleepyMochi() {
    var play = newPlay()
    run(&play, seconds: 0.1, speed: 1)
    #expect(play.phase == .watching)
    #expect(play.pose.frame.eyesOpen)
    #expect(play.pose.frame.wake == 1)
  }

  @Test func thePlayGoesInOrderAndEndsBackInBed() {
    var play = newPlay()
    run(&play, seconds: 0.1, speed: 1)
    let seen = phases(&play, seconds: 16)
    #expect(
      seen == [.watching, .crouching, .wiggling, .chasing, .pouncing, .proud, .returning, .resting])
    #expect(play.position == SIMD2(Self.bed.x, Self.bed.z))
  }

  @Test func watchingTurnsMochiToTheBall() {
    var play = newPlay()
    run(&play, seconds: 0.5, speed: 1)
    let offset = Self.far - SIMD2(Self.bed.x, Self.bed.z)
    let wanted = atan2(-offset.x, -offset.y)
    #expect(abs(remainder(play.pose.frame.heading - wanted, 2 * .pi)) < 0.05)
  }

  @Test func aBallThatNeverStopsStillGetsChased() {
    var play = newPlay()
    run(&play, seconds: 3.6, speed: 1)
    #expect(play.phase == .crouching || play.phase == .wiggling)
  }

  @Test func theProudSitIsOnTopOfTheBallAndHoldsIt() {
    var play = newPlay()
    run(&play, seconds: 0.1, speed: 1)
    while play.phase != .proud { run(&play, seconds: Self.step) }
    #expect(play.holdsBall)
    #expect(simd_distance(play.position, Self.far) < 0.001)
    #expect(play.pose.spot.y >= NookiYarnPlay.ballHeight)
  }

  @Test func aProudMochiTurnsToTheViewer() {
    var play = newPlay()
    run(&play, seconds: 0.1, speed: 1)
    while play.phase != .proud { run(&play, seconds: Self.step) }
    run(&play, seconds: 1.5)
    let wanted = atan2(-Float(0.6), -Float(0.8))
    #expect(abs(remainder(play.pose.frame.heading - wanted, 2 * .pi)) < 0.05)
  }

  @Test func aDeliveryCallsMochiBack() {
    var play = newPlay()
    run(&play, seconds: 0.1, speed: 1)
    while play.phase != .chasing { run(&play, seconds: Self.step) }
    run(&play, seconds: 0.3)
    run(&play, seconds: Self.step, canPlay: false)
    #expect(play.phase == .returning)
    run(&play, seconds: 2, canPlay: false)
    #expect(play.phase == .resting)
  }

  @Test func nothingStartsDuringADelivery() {
    var play = newPlay()
    run(&play, seconds: 1, speed: 1, canPlay: false)
    #expect(play.phase == .resting)
  }

  @Test func reduceMotionLooksFromTheBedAndNeverLeaves() {
    var play = newPlay()
    run(&play, seconds: 0.1, speed: 1, reduceMotion: true)
    #expect(play.pose.frame.eyesOpen)
    let seen = (0..<600).map { _ -> NookiYarnPlay.Phase in
      run(&play, seconds: Self.step, reduceMotion: true)
      return play.phase
    }
    #expect(!seen.contains(.chasing))
    #expect(!seen.contains(.crouching))
    #expect(play.position == SIMD2(Self.bed.x, Self.bed.z))
  }
}

@Suite struct NookiPhysicsRulesTests {
  private static let yaw: Float = 0.675

  @Test func leaningRightPushesRightOnScreen() {
    let push = NookiPhysics.push(lean: [0.2, 0], cameraYaw: Self.yaw)
    let right = SIMD3<Float>(cos(Self.yaw), 0, -sin(Self.yaw))
    #expect(simd_dot(push, right) > 1)
    #expect(push.y == 0)
  }

  @Test func leaningTheTopAwayPushesAway() {
    let push = NookiPhysics.push(lean: [0, -0.2], cameraYaw: Self.yaw)
    let away = SIMD3<Float>(-sin(Self.yaw), 0, -cos(Self.yaw))
    #expect(simd_dot(push, away) > 1)
  }

  @Test func noLeanPushesNothing() {
    #expect(NookiPhysics.push(lean: .zero, cameraYaw: Self.yaw) == .zero)
  }

  @Test func tiltAndFlickHaveCeilings() {
    #expect(simd_length(NookiPhysics.push(lean: [1, 1], cameraYaw: 0)) <= 2.5001)
    let flick = NookiPhysics.flick(screenVelocity: [9000, 0], cameraYaw: 0)
    #expect(simd_length(flick) <= 2.4001)
  }

  @Test func aSwipeUpThrowsAway() {
    let flick = NookiPhysics.flick(screenVelocity: [0, -500], cameraYaw: 0)
    #expect(flick.z < 0)
  }

  @Test func aBallOutsideTheRoomIsLost() {
    #expect(!NookiPhysics.isLost([0, 0.1, 0]))
    #expect(NookiPhysics.isLost([0.9, 0.1, 0]))
    #expect(NookiPhysics.isLost([0, -1, 0]))
  }
}
