import CoreGraphics
import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite("Light switch")
struct LightSwitchTests {
  private let own: (led: LightingLook.RGB, outside: LightingLook.RGB) = (
    [1, 0.9, 0.7], [1, 0.85, 0.6]
  )

  @Test func onKeepsThePresetCosyAndOffHaveTheirOwnLooks() {
    for lighting in RoomLighting.allCases {
      let preset = LightingLook.of(lighting)
      #expect(LightingLook.switched(preset, to: .on) == preset)
      #expect(LightingLook.switched(preset, to: .cosy) == .cosy)
      #expect(LightingLook.switched(preset, to: .off) == .moonlight)
    }
  }

  @Test func cosyIsTheLampLowAndTheFairyLightsOffIsNeither() {
    #expect(LightingLook.cosy.fairy.shown)
    #expect(LightingLook.cosy.key.boost < LightingLook.amberLantern.key.boost)
    #expect(!LightingLook.moonlight.fairy.shown)
    #expect(LightingLook.moonlight.key.boost == 0)
    #expect(LightingLook.moonlight.fill.shift < LightingLook.cosy.fill.shift)
    #expect(GenzLightSwitch.lampLevel(.off) == 0)
    #expect(GenzLightSwitch.lampLevel(.cosy) < GenzLightSwitch.lampLevel(.on))
  }

  @Test func aFadeStartsAtOneLookAndEndsAtTheOther() {
    let from = LightingLook.amberLantern
    let to = LightingLook.moonlight
    #expect(LightingLook.mix(from, to, by: 0, ownLED: own.led, ownOutside: own.outside) == from)
    #expect(LightingLook.mix(from, to, by: 1, ownLED: own.led, ownOutside: own.outside) == to)
    let half = LightingLook.mix(from, to, by: 0.5, ownLED: own.led, ownOutside: own.outside)
    #expect(half.fill.shift == (from.fill.shift + to.fill.shift) / 2)
    #expect(half.key.boost == (from.key.boost + to.key.boost) / 2)
  }

  @Test func fairyLightsFadeOutRatherThanVanish() {
    let half = LightingLook.mix(
      .cosy, .moonlight, by: 0.5, ownLED: own.led, ownOutside: own.outside)
    #expect(half.fairy.shown)
    #expect(half.fairy.spill == LightingLook.cosy.fairy.spill / 2)
  }

  @Test func materialColoursMoveInTenthsSoAFadeMakesFewMaterials() {
    var bulbs = Set<GenzColour>()
    for frame in 0...60 {
      let look = LightingLook.mix(
        .cosy, .moonlight, by: Float(frame) / 60, ownLED: own.led, ownOutside: own.outside)
      bulbs.insert(look.fairy.colour.genz)
      bulbs.insert((look.led ?? own.led).genz)
    }
    #expect(bulbs.count <= 24)
  }

  @Test func theFadeEasesOutAndEnds() {
    #expect(GenzLightSwitch.progress(0, length: 0.5) == 0)
    #expect(GenzLightSwitch.progress(0.25, length: 0.5) > 0.5)
    #expect(GenzLightSwitch.progress(0.5, length: 0.5) == 1)
    #expect(GenzLightSwitch.progress(2, length: 0.5) == 1)
    #expect(GenzLightSwitch.progress(0.1, length: 0) == 1)
  }

  @Test func theRockerTipsUpForOnAndDownForOff() {
    #expect(GenzLightSwitch.rockerLift(.on) > GenzLightSwitch.rockerLift(.cosy))
    #expect(GenzLightSwitch.rockerLift(.cosy) > GenzLightSwitch.rockerLift(.off))
  }
}

@MainActor
@Suite("Light switch in the room")
struct LightSwitchRoomTests {
  private let size = CGSize(width: 393, height: 852)

  @Test func thePlateIsOnScreenFromHomeInEveryFurnitureSet() throws {
    let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 60)
    for furniture in RoomFurniture.allCases {
      let camera = GenzCamera(home: GenzLayout.of(furniture).camera)
      let point = try #require(camera.project(GenzLightSwitch.plate.scene, in: size))
      #expect(bounds.contains(point), "\(furniture)")
    }
  }

  @Test func aTapOnThePlateCyclesTheLightAndTellsTheHost() async throws {
    let layout = GenzLayout.of(.original)
    let room = GenzRoomCache(suite: "light-switch-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(60)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    room.setLighting(.amberLantern)
    let plate = try #require(room.root.findEntity(named: GenzRoom.switchName))
    #expect(plate.components[CollisionComponent.self] != nil)
    #expect(room.tap(plate, at: 0) == .lightSwitched(.cosy))
    #expect(room.screen.switchPresses == 1)
    #expect(room.tap(plate, at: 5) == .lightSwitched(.off))
    #expect(room.tap(plate, at: 10) == .lightSwitched(.on))
  }

  @Test func theRoomGoesStraightToTheLightWhileOffScreen() async throws {
    let layout = GenzLayout.of(.original)
    let room = GenzRoomCache(suite: "light-switch-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(60)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    room.setLighting(.amberLantern)
    room.setRoomLight(.off)
    #expect(room.look == .moonlight)
    #expect(room.screen.look == .moonlight)
    #expect(room.lightSwitch.lampLevel == 0)
    room.setRoomLight(.on)
    #expect(room.look == .amberLantern)
  }
}
