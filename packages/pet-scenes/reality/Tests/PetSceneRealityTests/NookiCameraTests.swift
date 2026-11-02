import Testing
import simd

@testable import PetSceneReality

@Suite("NookiCamera")
struct NookiCameraTests {
  private func settled(_ camera: NookiCamera) -> NookiCamera {
    var camera = camera
    for _ in 0..<600 where !camera.isAtRest { camera.step(1.0 / 60) }
    return camera
  }

  private func released(_ camera: NookiCamera) -> NookiCamera {
    var camera = camera
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: true)
    return camera
  }

  @Test func startsAtRestAtHome() {
    #expect(NookiCamera().isAtRest)
  }

  @Test func staysOutsideTheWallsAndAboveTheFloorAtEveryExtreme() {
    for yaw: Float in [-9, 9] {
      for pitch: Float in [-9, 9] {
        for scale: Float in [0.01, 100] {
          var camera = NookiCamera()
          for _ in 0..<50 {
            camera.drag(yaw: yaw, pitch: pitch)
            camera.zoom(by: scale)
          }
          #expect(camera.position.x > -0.6)
          #expect(camera.position.z > -0.6)
          #expect(camera.position.y > 0)
        }
      }
    }
  }

  @Test func aTallNarrowViewStandsBackAndAWideOneDoesNot() {
    var wide = NookiCamera()
    wide.fit(to: [402, 300])
    #expect(wide.position == NookiCamera().position)

    var tall = NookiCamera()
    tall.fit(to: [402, 804])
    #expect(simd_distance(tall.position, NookiCamera.target) > tall.distance)
  }

  @Test func theFitOutlastsTheTripHome() {
    var camera = NookiCamera()
    camera.fit(to: [402, 804])
    camera.goHome(animated: false)
    #expect(camera.standBack > 1)
  }

  @Test func dragPastALimitEasesBackToIt() {
    var camera = NookiCamera()
    camera.drag(yaw: 9, pitch: 0)
    #expect(camera.yaw > NookiCamera.yawLimits.upperBound)
    #expect(settled(released(camera)).yaw == NookiCamera.yawLimits.upperBound)
  }

  @Test func zoomPastALimitEasesBackToIt() {
    var camera = NookiCamera()
    camera.zoom(by: 100)
    #expect(camera.distance < NookiCamera.distanceLimits.lowerBound)
    #expect(settled(released(camera)).distance == NookiCamera.distanceLimits.lowerBound)
  }

  @Test func coastsAfterReleaseAndComesToRest() {
    var camera = NookiCamera()
    let start = camera.yaw
    camera.drag(yaw: 0, pitch: 0)
    camera.release(yawVelocity: 0.4, pitchVelocity: 0, coasting: true)
    camera.step(1.0 / 60)
    #expect(camera.yaw > start)
    #expect(!camera.isAtRest)
    #expect(settled(camera).isAtRest)
  }

  @Test func reduceMotionNeitherCoastsNorOvershoots() {
    var camera = NookiCamera()
    camera.drag(yaw: 9, pitch: 0)
    camera.release(yawVelocity: 3, pitchVelocity: 3, coasting: false)
    #expect(camera.yaw == NookiCamera.yawLimits.upperBound)
    #expect(camera.isAtRest)
  }

  @Test func goingHomeIsSmoothAndEndsExactlyAtHome() {
    var camera = NookiCamera()
    camera.drag(yaw: 0.5, pitch: 0.3)
    camera.zoom(by: 1.3)
    camera.goHome(animated: true)
    let far = camera.yaw
    camera.step(1.0 / 60)
    #expect(camera.yaw != far)
    #expect(camera.yaw != NookiCamera().yaw)
    #expect(settled(camera) == NookiCamera())
  }

  @Test func goingHomeWithoutAnimationIsImmediate() {
    var camera = NookiCamera()
    camera.drag(yaw: 0.5, pitch: 0.3)
    camera.goHome(animated: false)
    #expect(camera == NookiCamera())
  }

  @Test func touchingTheCameraStopsTheTripHome() {
    var camera = NookiCamera()
    camera.drag(yaw: 0.5, pitch: 0)
    camera.goHome(animated: true)
    camera.drag(yaw: 0.01, pitch: 0)
    #expect(!camera.isReturningHome)
  }

  @Test func leanSwingsTheViewAndLeavesTheOrbitAlone() {
    var camera = NookiCamera()
    let before = (camera.yaw, camera.position)
    camera.lean(to: [0.1, 0])
    #expect(camera.yaw == before.0)
    #expect(camera.position != before.1)
  }

  @Test func leanStaysInsideTheOrbitLimits() {
    var camera = NookiCamera()
    camera.drag(yaw: 10, pitch: 10)
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: false)
    let atLimit = camera.position
    camera.lean(to: [NookiTilt.reach, NookiTilt.reach])
    #expect(camera.position == atLimit)
  }

  @Test func leanAddsToADrag() {
    var dragged = NookiCamera()
    dragged.drag(yaw: 0.2, pitch: 0)
    var both = dragged
    both.lean(to: [-0.2, 0])
    #expect(simd_distance(both.position, NookiCamera().position) < 0.001)
  }

  @Test func goingHomeKeepsTheLean() {
    var camera = NookiCamera()
    camera.lean(to: [0.1, 0.05])
    camera.goHome(animated: false)
    #expect(camera.lean == [0.1, 0.05])
  }
}
