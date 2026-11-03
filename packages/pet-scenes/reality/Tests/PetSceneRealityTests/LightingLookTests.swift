import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
struct LightingLookTests {
  @Test func offAddsNothing() {
    let look = LightingLook.of(.off)
    #expect(!look.isLit)
    #expect(look.haze.cover == 0 && look.halos == 0 && look.shadows == 0)
    #expect(look.grade.tintAmount == 0 && look.grade.liftAmount == 0 && look.vignette.amount == 0)
  }

  @Test func everyPresetIsLitAndDifferent() {
    let lit = RoomLighting.allCases.filter { $0 != .off }.map(LightingLook.of)
    #expect(lit.allSatisfy { $0.isLit })
    for (index, look) in lit.enumerated() {
      for other in lit.dropFirst(index + 1) { #expect(look != other) }
    }
  }

  @Test func theLanternHazeReplacesTheNightAndLiftsTheDarks() {
    let look = LightingLook.of(.amberLantern)
    #expect(look.haze.cover == 1)
    #expect(look.fairy.shown)
    #expect(look.grade.liftAmount > 0)
    // Warm: more red than blue everywhere it adds colour.
    #expect(look.haze.centre.x > look.haze.centre.z)
    #expect(look.grade.lift.x > look.grade.lift.z)
  }

  @Test func onlyTheCandleFlickersAndOnlyGoldenHourHasASun() {
    for lighting in RoomLighting.allCases {
      let look = LightingLook.of(lighting)
      #expect((look.key.flicker > 0) == (lighting == .candle))
      #expect((look.sun.intensity > 0) == (lighting == .goldenHour))
    }
  }

  @Test func neonNightTurnsTheLEDPinkAndTheWindowCool() throws {
    let look = LightingLook.of(.neonNight)
    let led = try #require(look.led)
    let outside = try #require(look.outside)
    #expect(led.x > led.y && led.z > led.y)
    #expect(outside.z > outside.x)
  }

  @Test func coloursBecomeRoomColours() {
    #expect(LightingLook.RGB(1, 0.5, 0).genz == GenzColour(0xFF8000))
    #expect(LightingLook.RGB(2, -1, 0).genz == GenzColour(0xFF0000))
    #expect(LightingLook.RGB.mix([0, 0, 0], [1, 1, 1], by: 0.25) == [0.25, 0.25, 0.25])
  }

  @Test func aFlameStaysBetweenItsDimmestAndFull() {
    #expect(GlowLights.flicker(0, time: 3) == 1)
    for step in 0..<200 {
      let level = GlowLights.flicker(0.22, time: Double(step) * 0.037)
      #expect(level <= 1 && level >= 1 - 0.22 - 1e-9)
    }
  }

  @Test func aStringDroopsMostInTheMiddleAndEndsOnItsHooks() {
    let hooks = [GenzRoomPoint(0, 0, 5), GenzRoomPoint(2, 0, 5)]
    let points = GenzGlow.string(hooks, spacing: 0.25, sag: 0.3)
    #expect(points.first == hooks.first && points.last == hooks.last)
    let lowest = points.map(\.z).min() ?? 5
    #expect(abs(lowest - 4.7) < 0.01)
  }

  @Test func onlyWindowSeatHangsFairyLights() {
    #expect(!GenzGlow.fairyHooks(.windowSeat).isEmpty)
    #expect(GenzGlow.fairyHooks(.sunsetLamp).isEmpty)
    #expect(GenzGlow.fairyHooks(.nooki).isEmpty)
  }

  @Test func eachFairyStringIsTwoModelsAndOneLightWithEveryBulbInIt() throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: .cosyNook))
    let glow = GenzGlow(layout: layout, kit: GenzKit())
    let fairy = try #require(glow.root.children.first)
    let strands = Array(fairy.children.filter { !$0.children.isEmpty })
    #expect(strands.count == GenzGlow.fairyHooks(.windowSeat).count)
    for strand in strands {
      #expect(strand.children.filter { $0.components.has(ModelComponent.self) }.count == 2)
    }
    let spills = fairy.children.filter { $0.components.has(PointLightComponent.self) }
    #expect(spills.count == strands.count)
    var bounds = BoundingBox()
    for strand in strands {
      for model in strand.children
      where model.components[ModelComponent.self]?.materials.first is UnlitMaterial {
        bounds = bounds.union(model.visualBounds(relativeTo: fairy))
      }
    }
    for point in glow.bulbPoints {
      let bulb = point.scene - [0, GenzGlow.bulbRadius + GenzGlow.wireThickness, 0]
      #expect(bounds.contains(bulb))
    }
  }

  @Test func aShadowIsDarkInTheMiddleAndClearAtTheEdge() throws {
    let image = try #require(GenzGlow.falloff(pixels: 16))
    let data = try #require(image.dataProvider?.data as Data?)
    let row = image.bytesPerRow
    #expect(data[8 * row + 8 * 4 + 3] > 200)
    #expect(data[3] < 10)
  }

  @Test func spotsAlongAPathAreEvenAndReachItsEnd() {
    let points = GlowSpots.along([GenzRoomPoint(0, 0, 0), GenzRoomPoint(2, 0, 0)], every: 0.5)
    #expect(points.count == 5)
    #expect(points.last == GenzRoomPoint(2, 0, 0))
  }

  @Test func frameStatsSummariseTheSlowFrames() throws {
    let intervals = Array(repeating: 1.0 / 60, count: 95) + Array(repeating: 0.05, count: 5)
    let summary = try #require(FrameStats.summary(intervals))
    #expect(abs(summary.slowest - 0.05) < 1e-9)
    #expect(abs(summary.slowTwentieth - 0.05) < 1e-9)
    #expect(summary.average > 1.0 / 60)
    #expect(FrameStats.summary([]) == nil)
  }
}
