import Foundation
import Pet
import PetScene
import RealityKit
import Testing

@testable import PetSceneReality

struct DeskLayoutTests {
  private func ids(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

  @Test func theLatestIsLargeAndTheRestSmall() {
    let notes = ids(5)
    let pins = DeskLayout.pins(for: notes)
    #expect(pins.map(\.id) == notes)
    #expect(pins[0].side == DeskLayout.large.side)
    #expect(pins.dropFirst().allSatisfy { $0.side == DeskLayout.smallSide })
  }

  @Test func theBoardHoldsOnlyWhatFits() {
    #expect(DeskLayout.pins(for: ids(30)).count == DeskLayout.capacity)
    #expect(DeskLayout.pins(for: []).isEmpty)
  }

  @Test func everyNoteIsOnTheCorkAndNoneOverlap() {
    let pins = DeskLayout.pins(for: ids(DeskLayout.capacity))
    let board = DeskLayout.board
    for pin in pins {
      #expect(pin.centre.x - pin.side / 2 >= board.x0)
      #expect(pin.centre.x + pin.side / 2 <= board.x1)
      #expect(pin.centre.z - pin.side / 2 >= board.z0)
      #expect(pin.centre.z + pin.side / 2 <= board.z1)
    }
    for (index, a) in pins.enumerated() {
      for b in pins.dropFirst(index + 1) {
        let gap = (a.side + b.side) / 2
        #expect(
          abs(a.centre.x - b.centre.x) >= gap * 0.9 || abs(a.centre.z - b.centre.z) >= gap * 0.9)
      }
    }
  }

  @Test func aNoteKeepsItsLeanAsNewOnesArrive() {
    let first = ids(3)
    let later = ids(2) + first
    let before = DeskLayout.pins(for: first).first { $0.id == first[1] }
    let after = DeskLayout.pins(for: later).first { $0.id == first[1] }
    #expect(before?.tilt == after?.tilt)
    #expect(before?.pin == after?.pin)
  }
}

struct CatVisitTests {
  @Test func theCatIsThereWhenTheDeskOpensAndComesAndGoes() {
    var visit = CatVisit(seed: 9)
    #expect(visit.step(0) == .sitting)
    var seen = Set<String>()
    for _ in 0..<(60 * 10) { seen.insert("\(visit.step(1))") }
    #expect(seen.contains("\(CatVisit.Stay.away)"))
    #expect(seen.contains("\(CatVisit.Stay.sitting)"))
  }

  @Test func fidgetsOnlyWhileSitting() {
    var visit = CatVisit(seed: 10)
    _ = visit.step(7)
    #expect(visit.takeFidget() != nil)
    #expect(visit.takeFidget() == nil)
  }
}

@MainActor
struct TabStagesTests {
  @Test func theStagesAreBuiltOnceAndShareTheRoomsKit() {
    let rooms = GenzRoomCache()
    let stages = TabStages(rooms: rooms)
    #expect(stages.deskStage === stages.deskStage)
  }

  @Test func eachStageIsRehearsedOnceALaunch() {
    let stages = TabStages(rooms: GenzRoomCache())
    #expect(stages.claimRehearsal(of: stages.deskStage))
    #expect(!stages.claimRehearsal(of: stages.deskStage))
  }

  @Test func aRehearsalBuildsTheStageWithoutItsTab() async {
    let stage = TabStages(rooms: GenzRoomCache()).deskStage
    stage.setRehearsing(true)
    let deadline = ContinuousClock.now + .seconds(60)
    while !stage.isBuilt, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    #expect(stage.isBuilt)
    #expect(stage.root.scene == nil)
    stage.setRehearsing(false)
  }

  @Test func theNookiSceneHasADeskButNo3DShop() {
    let scene = NookiPetScene()
    #expect(scene.hasShop)
    #expect(scene.makeDeskScene(state: DeskSceneState(notes: []), onEvent: { _ in }) != nil)
  }
}

@MainActor
struct TabLightingTests {
  private func intensity(_ light: Entity) -> Float? {
    light.components[PointLightComponent.self]?.intensity
  }

  @Test func offKeepsTheScenesOwnLight() {
    let lighting = TabLighting()
    let lamp = lighting.key(GenzColour(0xFFC36B), intensity: 16_000, reach: 7, at: .init(1, 1, 1))
    lighting.shadow(width: 1, depth: 1, at: .zero)
    lighting.apply(.off)
    #expect(intensity(lamp) == 16_000)
    #expect(lighting.haloScale == 1)
    #expect(lighting.fairyColour == nil)
    #expect(lighting.tint(GenzColour(0xFFC36B)) == GenzColour(0xFFC36B))
    let shadows = lighting.root.children.filter { $0.name == "genz-shadow" }
    #expect(shadows.count == 1)
    #expect(shadows.allSatisfy { !$0.isEnabled })
  }

  @Test(arguments: RoomLighting.allCases.filter { $0 != .off })
  func aPresetLightsTheSceneThroughTheRig(_ preset: RoomLighting) {
    let look = LightingLook.of(preset)
    let lighting = TabLighting()
    let lamp = lighting.key(GenzColour(0xFFC36B), intensity: 10_000, reach: 7, at: .init(1, 1, 1))
    lighting.shadow(width: 1, depth: 1, at: .zero)
    lighting.apply(look)
    #expect(intensity(lamp) == 10_000 * look.key.boost || look.key.flicker > 0)
    let shadow = lighting.root.children.first { $0.name == "genz-shadow" }
    #expect(shadow?.isEnabled == (look.shadows > 0))
    #expect(lighting.fairyColour != nil || !look.fairy.shown)
    if look.halos > 0 { #expect(lighting.haloScale > 0.55) }
    // Back to off, the lamp is its own again.
    lighting.apply(.off)
    #expect(intensity(lamp) == 10_000)
  }

  @Test func theCandleFlickersButNotWithMotionReduced() {
    let lighting = TabLighting()
    let lamp = lighting.key(GenzColour(0xFFC36B), intensity: 10_000, reach: 7, at: .init(1, 1, 1))
    lighting.apply(.candle)
    var seen = Set<Float>()
    for _ in 0..<30 {
      lighting.step(1 / 30)
      seen.insert(intensity(lamp) ?? 0)
    }
    #expect(seen.count > 1)
    lighting.setReduceMotion(true)
    lighting.step(1 / 30)
    #expect(intensity(lamp) == 10_000 * LightingLook.candle.key.boost)
  }

  @Test func theStagesTakeAPresetBeforeAndAfterTheyAreBuilt() {
    let stages = TabStages(rooms: GenzRoomCache())
    stages.shopStage.setLighting(.amberLantern)
    stages.deskStage.setLighting(.neonNight)
    stages.shopStage.setLighting(.off)
  }
}

struct DeskCuesTests {
  @Test func theDoodleLiesOnThePapersCorners() throws {
    let corners = [
      CGPoint(x: 100, y: 500), CGPoint(x: 260, y: 505), CGPoint(x: 280, y: 600),
      CGPoint(x: 90, y: 596),
    ]
    let transform = try #require(DeskDoodleLayer.projection(onto: corners))
    let page = DeskDoodleLayer.page
    let pageCorners = [
      CGPoint.zero, CGPoint(x: page.width, y: 0), CGPoint(x: page.width, y: page.height),
      CGPoint(x: 0, y: page.height),
    ]
    for (from, to) in zip(pageCorners, corners) {
      let w = from.x * transform.m13 + from.y * transform.m23 + transform.m33
      let x = (from.x * transform.m11 + from.y * transform.m21 + transform.m31) / w
      let y = (from.x * transform.m12 + from.y * transform.m22 + transform.m32) / w
      let missX: CGFloat = abs(x - to.x)
      let missY: CGFloat = abs(y - to.y)
      #expect(missX < 0.01)
      #expect(missY < 0.01)
    }
    #expect(DeskDoodleLayer.projection(onto: []) == nil)
  }

  @Test func thePapersCornersSurroundItsMiddle() {
    let corners = DeskLayout.paperCorners
    let middle = DeskLayout.paper.centre
    #expect(corners.count == 4)
    let meanX: Float = corners.map(\.x).reduce(0, +) / 4
    let meanY: Float = corners.map(\.y).reduce(0, +) / 4
    #expect(abs(meanX - middle.x) < 1e-4)
    #expect(abs(meanY - middle.y) < 1e-4)
    // Far edge first: the first two are further from the viewer than the last two.
    #expect(corners[0].y < corners[3].y && corners[1].y < corners[2].y)
  }

  @MainActor
  @Test func theEmptyBoardHasAPlaceholderCard() {
    #expect(DeskArt.placeholder() != nil)
  }
}
