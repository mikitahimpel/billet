import CoreGraphics
import Pet
import PetScene
import Testing
import simd

@testable import PetSceneReality

@Suite struct SceneDirectionTests {
  @Test func theOpeningCuesTheCatOnceEachInOrder() {
    var flight = SceneFlight(id: 1, clock: 10, atEnd: false)
    #expect(flight.dueCues(at: 10.5).isEmpty)
    #expect(flight.dueCues(at: 10 + FlyInTimeline.wake) == [.wakeUp])
    #expect(flight.dueCues(at: 10 + FlyInTimeline.wake + 0.1).isEmpty)
    #expect(flight.dueCues(at: 10 + FlyInTimeline.length) == [.lookAtCamera])
    #expect(flight.isOver(at: 10 + FlyInTimeline.length))
  }

  @Test func aSkipEndsTheOpeningWithoutItsCues() {
    var flight = SceneFlight(id: 1, clock: 0, atEnd: false)
    flight.skip(at: 0.5)
    #expect(flight.isOver(at: 0.5))
    #expect(flight.dueCues(at: 0.5).isEmpty)
  }

  @Test func anOpeningStartedAtItsEndIsAlreadyOver() {
    var flight = SceneFlight(id: 2, clock: 4, atEnd: true)
    #expect(flight.isOver(at: 4))
    #expect(flight.dueCues(at: 4).isEmpty)
  }

  @Test func theFlightHoldsTheNookiCameraFurtherOut() {
    var camera = NookiCamera()
    let home = camera.position
    camera.fly(yaw: 0.5, pitch: 0.2, distance: 2)
    #expect(
      simd_length(camera.position - NookiCamera.target)
        > simd_length(home - NookiCamera.target) * 1.9)
    camera.fly(yaw: 0, pitch: 0, distance: 1)
    #expect(simd_distance(camera.position, home) < 0.0001)
  }

  @Test func aFilledViewBringsTheNookiCameraCloser() {
    var fitted = NookiCamera()
    fitted.fit(to: [393, 852])
    var filled = NookiCamera()
    filled.fit(to: [393, 852], fills: true)
    #expect(filled.standBack < fitted.standBack)
  }

  @MainActor
  @Test func aPointOnTheFloorComesBackUnderItsOwnSpot() throws {
    let camera = GenzCamera(home: GenzLayout.windowSeat.camera)
    let size = CGSize(width: 393, height: 852)
    let floor = SIMD3<Float>(4, 0.5, 3)
    let spot = try #require(camera.project(floor, in: size))
    let back = try #require(camera.point(under: spot, in: size, height: 0.5))
    #expect(simd_distance(back, floor) < 0.01)
  }

  @Test func dayIsBrighterThanNightAndTheLampFollowsTheHour() {
    let noon = RoomDayLook(DayLight.at(hour: 13))
    let night = RoomDayLook(DayLight.at(hour: 23))
    #expect(noon.sunIntensity > night.sunIntensity * 5)
    #expect(noon.ambientShift > night.ambientShift)
    #expect(!noon.lampOn && night.lampOn)
  }

  @Test func theirSkyGlowsLessAtNight() {
    #expect(
      RoomDayLook.sky(DayLight.at(hour: 2)).glow < RoomDayLook.sky(DayLight.at(hour: 12)).glow)
  }

  @Test func aWokenCatIsUpAndThenSettlesBack() {
    #expect(NookiMotion.wake(1, reduceMotion: false).wake == 1)
    #expect(NookiMotion.wake(1, reduceMotion: false).eyesOpen)
    #expect(NookiMotion.wake(1, reduceMotion: false).hop == 0)
    #expect(NookiMotion.wake(NookiMotion.wakeLength, reduceMotion: false) == NookiFrame())
    #expect(NookiMotion.wake(1, reduceMotion: true).wake == 0)
  }
}
