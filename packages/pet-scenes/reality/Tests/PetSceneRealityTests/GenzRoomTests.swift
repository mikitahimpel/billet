import CoreGraphics
import Foundation
import Pet
import PetScene
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzRoomTests {
  private let size = CGSize(width: 393, height: 852)

  @Test func nookiOffersEveryRoomStyle() {
    #expect(NookiPetScene().roomStyles == RoomStyle.allCases)
  }

  @Test func onlyTheStyledRoomsHaveALayout() {
    #expect(GenzLayout.of(.nooki) == nil)
    #expect(GenzLayout.of(.sunsetLamp)?.style == .sunsetLamp)
    #expect(GenzLayout.of(.windowSeat)?.style == .windowSeat)
  }

  @Test func theCameraTargetLandsInTheMiddleOfTheView() throws {
    for style in [RoomStyle.sunsetLamp, .windowSeat] {
      let camera = GenzCamera(home: try #require(GenzLayout.of(style)).camera)
      let point = try #require(camera.project(camera.target, in: size))
      #expect(abs(point.x - size.width / 2) < 0.5)
      #expect(abs(point.y - size.height / 2) < 0.5)
    }
  }

  @Test func projectionKeepsLeftLeftAndUpUp() throws {
    let camera = GenzCamera(home: GenzLayout.sunsetLamp.camera)
    let target = camera.target
    let up = try #require(camera.project(target + [0, 1, 0], in: size))
    #expect(up.y < size.height / 2)
    let back = try #require(camera.project(target + [0, 0, -1], in: size))
    let front = try #require(camera.project(target + [0, 0, 1], in: size))
    #expect(back.y < front.y)
    #expect(camera.project(camera.position - (target - camera.position), in: size) == nil)
  }

  @Test(arguments: [RoomStyle.sunsetLamp, .windowSeat])
  func theCatAndTheNoteAreOnScreenFromHome(_ style: RoomStyle) throws {
    let layout = try #require(GenzLayout.of(style))
    let camera = GenzCamera(home: layout.camera)
    let bounds = CGRect(origin: .zero, size: size)
    let cat = try #require(camera.project(layout.cat.spot.scene, in: size))
    #expect(bounds.contains(cat))
    for corner in layout.note.corners {
      let point = try #require(camera.project(corner.scene, in: size))
      #expect(bounds.insetBy(dx: -40, dy: 0).contains(point))
    }
  }

  @Test func dragAndPinchStayInsideTheLimits() {
    let home = GenzLayout.windowSeat.camera
    var camera = GenzCamera(home: home)
    camera.drag(yaw: 10, pitch: -10)
    #expect(camera.yaw == home.yawLimits.upperBound)
    #expect(camera.pitch == home.pitchLimits.lowerBound)
    camera.zoom(by: 0.01)
    #expect(camera.zoom == home.zoomLimits.upperBound)
    camera.goHome(animated: false)
    #expect(camera.yaw == home.yaw && camera.pitch == home.pitch && camera.zoom == 1)
  }

  @Test func goingHomeAnimatedArrives() {
    var camera = GenzCamera(home: GenzLayout.sunsetLamp.camera)
    camera.drag(yaw: 0.3, pitch: 0.1)
    camera.goHome(animated: true)
    for _ in 0..<300 { camera.step(1.0 / 60) }
    #expect(camera.isAtRest)
    #expect(camera.yaw == GenzLayout.sunsetLamp.camera.yaw)
  }

  @Test func theOpeningStartsDarkAndEndsLit() {
    #expect(GenzOpening.sunsetDim(0) > 0.8)
    #expect(GenzOpening.sunsetDim(GenzOpening.length) == 0)
    #expect(GenzOpening.lampClick(0.3) == 0)
    #expect(GenzOpening.lampClick(GenzOpening.length) == 1)
    #expect(GenzOpening.discBloom(0.4) == 0)
    #expect(GenzOpening.discBloom(GenzOpening.length) == 1)
    #expect(GenzOpening.sunsetNote(GenzOpening.length) == 1)
    #expect(GenzOpening.windowDim(0) == 0.75)
    #expect(GenzOpening.windowDim(GenzOpening.length) == 0)
    #expect(GenzOpening.streetLamp(0) == 0)
    #expect(GenzOpening.streetLamp(GenzOpening.length) == 1)
    #expect(GenzOpening.windowLED(GenzOpening.length) == 1)
  }

  @Test func theStreetLampStuttersBeforeItStaysOn() {
    let samples = stride(from: 0.3, through: 1.0, by: 0.02).map(GenzOpening.streetLamp)
    #expect(samples.contains(1))
    #expect(samples.contains { $0 > 0 && $0 < 0.5 })
  }

  @Test func theLEDStepsOnInThrees() {
    let levels = Set(stride(from: 0.0, through: 1.0, by: 0.01).map(GenzOpening.sunsetLED))
    #expect(levels == [0, 1.0 / 3, 2.0 / 3, 1])
  }

  @Test func theDiscBreathesBetweenItsBounds() {
    for time in stride(from: 0.0, through: 40, by: 0.25) {
      let breath = GenzOpening.discBreath(time)
      #expect(breath >= 0.86 - 1e-9 && breath <= 1)
    }
  }

  @Test func carsComeEveryTwelveToFortySeconds() {
    var starts: [Double] = []
    var wasPassing = false
    for step in 0..<(600 * 10) {
      let time = Double(step) / 10
      let passing = GenzOpening.headlight(time) != nil
      if passing, !wasPassing { starts.append(time) }
      wasPassing = passing
    }
    #expect(starts.first == 3)
    for (earlier, later) in zip(starts, starts.dropFirst()) {
      let gap = later - earlier - 2.6
      #expect(gap >= 11.9 && gap <= 40.1)
    }
  }

  @Test func warmthFadesAfterANoteLands() {
    #expect(GenzOpening.warmth(sinceLanding: nil) == 0)
    #expect(GenzOpening.warmth(sinceLanding: 0) == 1)
    #expect(GenzOpening.warmth(sinceLanding: 3) == 0.5)
    #expect(GenzOpening.warmth(sinceLanding: 10) == 0)
  }

  @Test(arguments: GenzPiece.Kind.allCases)
  func everyPieceHasTwoOrThreeColourSlots(_ kind: GenzPiece.Kind) {
    #expect((2...3).contains(kind.slotNames.count))
    #expect(kind.standardSlots.count == kind.slotNames.count)
    #expect(!kind.title.isEmpty)
  }

  @Test func piecesShareMeshesAndRecolourWithoutNewOnes() {
    let kit = GenzKit()
    for kind in GenzPiece.Kind.allCases { _ = kit.build(GenzPiece(kind)) }
    let meshes = kit.meshCount
    for kind in GenzPiece.Kind.allCases {
      let recoloured = GenzPiece(kind, slots: kind.standardSlots.map { $0.shaded(0.2) })
      _ = kit.build(recoloured)
    }
    #expect(kit.meshCount == meshes)
  }

  @Test func aRecolourChangesThePieceColours() {
    let piece = GenzPiece(.platformBed, slots: [GenzColour(0x111111)])
    #expect(piece.slot(0) == GenzColour(0x111111))
    #expect(piece.slot(2) == GenzPiece.Kind.platformBed.standardSlots[2])
  }

  @Test func layersWithAnOutlineGetOneFromTheRoom() {
    let room = GenzRoom(layout: GenzLayout.windowSeat, kit: GenzKit(), cats: GenzCatSource())
    room.fit(to: size)
    #expect(room.screen.outlines[.windowBloom]?.count == GenzLayout.windowSeat.led.count)
    #expect(room.screen.outlines[.windowBacklight]?.count == 4)
    #expect(room.screen.cat != nil)
  }

  @Test func nativeArtDrawsEveryTextureSlot() {
    let art = GenzNativeArt()
    for slot in RoomLayerSlot.allCases where slot.isTexture {
      let image = art.image(for: slot, state: RoomLayerState(time: 3), pixels: 64)
      #expect(image?.width == 64)
    }
    for slot in RoomLayerSlot.allCases where !slot.isTexture {
      #expect(art.view(for: slot, state: RoomLayerState()) != nil)
    }
  }

  @Test func roomsOutOfAnySceneLetGoAtOnce() async {
    let rooms = GenzRoomCache()
    _ = rooms.room(GenzLayout.sunsetLamp)
    let start = ContinuousClock.now
    await rooms.untilLetGo()
    // Well under the five seconds a view still holding its scene could take.
    #expect(ContinuousClock.now - start < .seconds(4))
  }

  @Test func theNoteLeavesTheDiscShowingAroundIt() throws {
    let wall = try #require(GenzLayout.sunsetLamp.discWall)
    #expect(GenzLayout.sunsetLamp.note.width < wall.width / 2)
    #expect(GenzLayout.windowSeat.note.width < 2)
  }

  @Test func theNoteTextureKeepsThePapersShape() {
    let image = GenzTextures.note(
      drawing: nil, paper: GenzColour(0xFFFFFF), aspect: 1.1, corners: true, pixels: 100)
    #expect(image?.width == 100)
    #expect(image?.height == 110)
  }
}
