import CoreGraphics
import Foundation
import Pet
import PetScene
import RealityKit
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

  @Test(arguments: [RoomStyle.sunsetLamp, .windowSeat])
  func theShellIsOneModelPerColour(_ style: RoomStyle) async throws {
    let layout = try #require(GenzLayout.of(style))
    let kit = GenzKit()
    let room = GenzRoom(
      layout: layout, kit: kit, cats: GenzCatSource(),
      spots: GenzSpotStore(defaults: UserDefaults(suiteName: "shell-\(UUID())")!, key: layout.key))
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(60)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    let shell = try #require(room.root.findEntity(named: GenzRoom.shellName))
    var keys: [MatteKey] = []
    var models = 0
    NookiDiorama.visit(shell) { entity in
      guard let model = entity as? ModelEntity else { return }
      models += 1
      if let material = model.model?.materials.first as? PhysicallyBasedMaterial,
        let key = MatteKey(material, textures: kit.textures)
      {
        keys.append(key)
      }
    }
    #expect(Set(keys).count == keys.count)
    #expect(models < layout.shell(GenzKit()).count)
  }

  @Test func dragAndPinchGiveALittleAtTheLimitsThenEaseBack() {
    let home = GenzLayout.windowSeat.camera
    var camera = GenzCamera(home: home)
    camera.drag(yaw: 10, pitch: -10)
    #expect(camera.yaw > home.yawLimits.upperBound)
    #expect(camera.yaw <= home.yawLimits.upperBound + GenzCamera.angleOvershoot)
    #expect(camera.pitch < home.pitchLimits.lowerBound)
    #expect(camera.pitch >= home.pitchLimits.lowerBound - GenzCamera.angleOvershoot)
    camera.zoom(by: 0.01)
    #expect(camera.zoom > home.zoomLimits.upperBound)
    #expect(camera.zoom <= home.zoomLimits.upperBound + GenzCamera.zoomOvershoot)
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: true)
    #expect(!camera.isAtRest)
    for _ in 0..<120 { camera.step(1.0 / 60) }
    #expect(camera.isAtRest)
    #expect(camera.yaw == home.yawLimits.upperBound)
    #expect(camera.pitch == home.pitchLimits.lowerBound)
    #expect(camera.zoom == home.zoomLimits.upperBound)
    camera.goHome(animated: false)
    #expect(camera.yaw == home.yaw && camera.pitch == home.pitch && camera.zoom == 1)
  }

  @Test func aDragFollowsOnlyPartWayPastALimit() {
    let home = GenzLayout.windowSeat.camera
    var camera = GenzCamera(home: home)
    camera.drag(yaw: home.yawLimits.upperBound - home.yaw, pitch: 0)
    camera.drag(yaw: 0.05, pitch: 0)
    #expect(abs(camera.yaw - (home.yawLimits.upperBound + 0.015)) < 0.0001)
  }

  @Test func aCoastIntoALimitSlowsPastItRatherThanStoppingDead() {
    let home = GenzLayout.windowSeat.camera
    var camera = GenzCamera(home: home)
    camera.drag(yaw: home.yawLimits.upperBound - 0.05 - home.yaw, pitch: 0)
    camera.release(yawVelocity: 1.5, pitchVelocity: 0, coasting: true)
    var furthest = camera.yaw
    var steps: [Float] = []
    for _ in 0..<180 {
      let was = camera.yaw
      camera.step(1.0 / 60)
      steps.append(abs(camera.yaw - was))
      furthest = max(furthest, camera.yaw)
    }
    #expect(furthest > home.yawLimits.upperBound)
    #expect(furthest <= home.yawLimits.upperBound + GenzCamera.angleOvershoot)
    #expect(camera.yaw == home.yawLimits.upperBound)
    #expect(camera.isAtRest)
    // No frame jumps further than the release speed carries it in one frame.
    #expect(steps.allSatisfy { $0 <= 1.5 / 60 + 0.0001 })
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
    let room = GenzRoomCache(suite: "genz-room-\(UUID())").room(GenzLayout.windowSeat)
    room.fit(to: size)
    #expect(room.screen.outlines[.windowBloom]?.count == GenzLayout.windowSeat.led.count)
    #expect(room.screen.outlines[.windowBacklight]?.count == 4)
    #expect(room.screen.cat != nil)
    // At rest the window is where the view's planes are laid out; a turn moves only the live one.
    #expect(room.screen.window.count == 4)
    #expect(room.screen.homeWindow == room.screen.window)
    room.orbit(byX: 80, y: 0)
    room.endOrbit(velocityX: 0, velocityY: 0)
    #expect(room.screen.window != room.screen.homeWindow)
  }

  @Test func theWindowShowsTheChosenViewInTheRoomsHour() {
    let room = GenzRoomCache(suite: "genz-room-\(UUID())").room(GenzLayout.windowSeat)
    room.setWindowView(WindowViewChoice(view: .suburbNight, weather: .rain))
    #expect(room.screen.viewHour == .night)
    room.show(dayLight: PetSceneDayLight(here: .at(hour: 13), theirs: nil))
    #expect(room.screen.viewHour == .day)
    room.setWindowView(WindowViewChoice(view: .suburbNight, hour: .dusk))
    #expect(room.screen.viewHour == .dusk)
    let state = room.screen.viewState(at: Date())
    #expect(state.weather == WindowView.suburbNight.weather)
    #expect(state.hour == .dusk)
  }

  @Test func nativeArtDrawsEveryTextureSlot() {
    let art = GenzNativeArt()
    for slot in RoomLayerSlot.allCases where slot.isTexture {
      let image = art.image(for: slot, state: RoomLayerState(time: 3), pixels: 64)
      #expect(image?.width == 64)
    }
    // The window's view is drawn by the view system, not by the room's own flat art.
    for slot in RoomLayerSlot.allCases where !slot.isTexture && slot != .windowNight {
      #expect(art.view(for: slot, state: RoomLayerState()) != nil)
    }
  }

  @Test func aRoomSeenBeforeIsShownAtOnceAndKeepsItsView() {
    var rooms = RoomSwitch()
    rooms.show(.nooki, hostShowsScene: true)
    rooms.show(.windowSeat, hostShowsScene: true)
    rooms.show(.nooki, hostShowsScene: false)
    #expect(rooms == RoomSwitch(mounted: [.diorama, .styled], shown: .nooki, styled: .windowSeat))
  }

  @Test func aNewViewWaitsForTheSceneToBeShown() {
    var rooms = RoomSwitch(mounted: [.diorama], shown: .nooki)
    rooms.show(.sunsetLamp, hostShowsScene: false)
    #expect(rooms == RoomSwitch(mounted: [.diorama], shown: .nooki))
    rooms.show(.sunsetLamp, hostShowsScene: true)
    #expect(
      rooms == RoomSwitch(mounted: [.diorama, .styled], shown: .sunsetLamp, styled: .sunsetLamp))
  }

  /// A second RealityView only draws its first frame, so the styled rooms take turns in one.
  @Test func theStyledRoomsShareOneView() {
    var rooms = RoomSwitch()
    rooms.show(.windowSeat, hostShowsScene: true)
    rooms.show(.sunsetLamp, hostShowsScene: false)
    #expect(rooms == RoomSwitch(mounted: [.styled], shown: .sunsetLamp, styled: .sunsetLamp))
    rooms.show(.nooki, hostShowsScene: true)
    rooms.show(.windowSeat, hostShowsScene: true)
    #expect(rooms.mounted == [.styled, .diorama])
    #expect(rooms.styled == .windowSeat)
  }

  @Test func eachRoomStyleHasItsView() {
    #expect(RoomStage(.nooki) == .diorama)
    #expect(RoomStage(.sunsetLamp) == .styled)
    #expect(RoomStage(.windowSeat) == .styled)
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
