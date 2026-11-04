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
    #expect(abs(half.fill.shift - (from.fill.shift + to.fill.shift) / 2) < 0.0001)
    #expect(abs(half.key.boost - (from.key.boost + to.key.boost) / 2) < 0.0001)
  }

  @Test func fairyLightsFadeOutRatherThanVanish() {
    let half = LightingLook.mix(
      .cosy, .moonlight, by: 0.5, ownLED: own.led, ownOutside: own.outside)
    #expect(half.fairy.shown)
    #expect(abs(half.fairy.spill - LightingLook.cosy.fairy.spill / 2) < 0.0001)
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

  @Test func theToggleIsUpWhileAnyLightIsOnAndDownWhenOff() {
    #expect(GenzLightSwitch.toggleStand(.on) == 1)
    #expect(GenzLightSwitch.toggleStand(.cosy) == 1)
    #expect(GenzLightSwitch.toggleStand(.off) == -1)
  }

  @Test func theDotGlowsOnlyWhileTheLightsAreOn() {
    #expect(GenzLightSwitch.indicatorLit(.on))
    #expect(GenzLightSwitch.indicatorLit(.cosy))
    #expect(!GenzLightSwitch.indicatorLit(.off))
  }

  @Test func voiceOverHearsOnOrOff() {
    #expect(GenzLightSwitch.spoken(.on) == "on")
    #expect(GenzLightSwitch.spoken(.cosy).hasPrefix("on"))
    #expect(GenzLightSwitch.spoken(.off) == "off")
  }

  @Test func theToggleFlipsAllTheWayAndEveryPressMovesIt() {
    let length = GenzLightSwitch.flipLength
    #expect(GenzLightSwitch.toggle(from: 1, to: -1, elapsed: 0) == 1)
    #expect(GenzLightSwitch.toggle(from: 1, to: -1, elapsed: length) == -1)
    #expect(GenzLightSwitch.toggle(from: -1, to: 1, elapsed: length / 2) == 0)
    // On to cosy leaves it up, but it still dips and comes back.
    #expect(GenzLightSwitch.toggle(from: 1, to: 1, elapsed: length / 2) < 0.6)
    #expect(GenzLightSwitch.toggle(from: 1, to: 1, elapsed: length) == 1)
  }

  @Test func thePlateIsBiggerThanItWasAndTheTapReachesWellPastIt() {
    #expect(GenzLightSwitch.plateSize.x > 0.34)
    #expect(GenzLightSwitch.plateSize.y > 0.56)
    #expect(GenzLightSwitch.reach.x > GenzLightSwitch.plateSize.x * 2)
    #expect(GenzLightSwitch.reach.y > GenzLightSwitch.plateSize.y * 1.8)
  }

  @Test func thePlateKeepsClearOfTheLEDStripAndTheCorner() {
    let layout = GenzLayout.windowSeat
    let half = GenzLightSwitch.plateSize.x / 2
    let ledLeft = layout.led.map(\.x).min() ?? 0
    #expect(GenzLightSwitch.plate.x - half > 0)
    #expect(GenzLightSwitch.plate.x + half < ledLeft)
  }

  @Test func thePulseSwellsOnceAndSettles() {
    #expect(GenzLightSwitch.pulseScale(0) == 1)
    #expect(GenzLightSwitch.pulseScale(GenzLightSwitch.pulseLength / 2) > 1.1)
    #expect(GenzLightSwitch.pulseScale(GenzLightSwitch.pulseLength) == 1)
  }

  @Test func thePulsePlaysOncePerInstall() throws {
    let suite = "light-switch-pulse-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(GenzLightSwitch.claimPulse(in: defaults))
    #expect(!GenzLightSwitch.claimPulse(in: defaults))
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

  @Test func nothingAnySetStandsInTheCornerHidesThePlate() {
    let bottom = GenzLightSwitch.plate.z - GenzLightSwitch.plateSize.y / 2
    let underPlate = SIMD2(GenzLightSwitch.plate.x, 0.3)
    for furniture in RoomFurniture.allCases {
      for placement in GenzLayout.of(furniture).pieces
      where GenzRoom.box(of: placement).contains(underPlate) {
        #expect(
          placement.centre.z + placement.piece.kind.size.z < bottom,
          "\(furniture): \(placement.piece.kind)")
      }
    }
  }

  @Test func aTapOnThePlateCyclesTheLightAndTellsTheHost() async throws {
    let layout = GenzLayout.of(.original)
    let room = GenzRoomCache(suite: "light-switch-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    room.setLighting(.amberLantern)
    let plate = try #require(room.root.findEntity(named: GenzRoom.switchName))
    #expect(plate.components[CollisionComponent.self] != nil)
    #expect(room.tap(plate, at: 0) == .lightSwitched(.cosy))
    #expect(room.screen.switchPresses == 1)
    #expect(room.tap(plate, at: 5) == .lightSwitched(.off))
    #expect(room.tap(plate, at: 10) == .lightSwitched(.on))
    #expect(room.screen.roomLight == .on)
  }

  @Test func theSwitchShowsWhereItStands() async throws {
    let layout = GenzLayout.of(.original)
    let room = GenzRoomCache(suite: "light-switch-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    room.setRoomLight(.off)
    #expect(room.lightSwitch.toggleAt == -1)
    #expect(room.screen.roomLight == .off)
    room.setRoomLight(.on)
    #expect(room.lightSwitch.toggleAt == 1)
    let toggle = try #require(room.lightSwitch.toggle)
    #expect(toggle.position.y > 0)
    room.fit(to: CGSize(width: 393, height: 852))
    #expect(room.screen.lightSwitch != nil)
  }

  @Test func theRoomGoesStraightToTheLightWhileOffScreen() async throws {
    let layout = GenzLayout.of(.original)
    let room = GenzRoomCache(suite: "light-switch-\(UUID())").room(layout)
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    room.setLighting(.amberLantern)
    room.setRoomLight(.off)
    #expect(room.look == .moonlight)
    #expect(room.screen.look == .moonlight)
    #expect(room.lightSwitch.lampLevel == 0)
    #expect(room.screen.ledLevel == 0)
    #expect(room.screen.state(for: .windowBloom, at: .now).ledLevel == 0)
    room.setRoomLight(.on)
    #expect(room.look == .amberLantern)
  }
}
