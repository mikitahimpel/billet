import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

/// Faces of two colours in one plane flicker as the camera turns, so no room may have any where
/// the camera can see them.
@MainActor
@Suite struct FlushFacesTests {
  /// Where the camera can stand: home, and each corner of its turn and tilt, near and far.
  private func eyes(_ home: GenzCamera.Home) -> [SIMD3<Float>] {
    var eyes = [GenzCamera(home: home).position]
    // Out to where a drag past a limit can carry the camera before it eases back.
    let give = GenzCamera.angleOvershoot
    let zoomGive = GenzCamera.zoomOvershoot
    for yaw in [home.yawLimits.lowerBound - give, home.yawLimits.upperBound + give] {
      for pitch in [home.pitchLimits.lowerBound - give, home.pitchLimits.upperBound + give] {
        for zoom in [home.zoomLimits.lowerBound - zoomGive, home.zoomLimits.upperBound + zoomGive] {
          var camera = GenzCamera(home: home)
          camera.drag(yaw: yaw - home.yaw, pitch: pitch - home.pitch)
          camera.zoom(by: 1 / zoom)
          eyes.append(camera.position)
        }
      }
    }
    return eyes
  }

  @Test(arguments: RoomFurniture.allCases)
  func theRoomHasNoFlushFaces(_ furniture: RoomFurniture) async throws {
    let layout = GenzLayout.of(furniture)
    let room = GenzRoom(
      layout: layout, kit: GenzKit(), cats: GenzCatSource(),
      spots: GenzSpotStore(defaults: UserDefaults(suiteName: "flush-\(UUID())")!, key: layout.key))
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(60)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    let clashes = FlushFaces.clashes(
      under: [room.root], seenFrom: eyes(layout.camera),
      // The cat moves, and the light dot only shows on a trip, on whatever it lands on.
      skip: { [GenzRoom.catName, GenzRoom.lightDotName].contains($0.name) })
    #expect(clashes.isEmpty, "\(clashes)")
  }

  @Test func theShopHasNoFlushFaces() async throws {
    let shop = ShopStage(kit: GenzKit())
    shop.start()
    defer { shop.setOnScreen(false) }
    let deadline = Date.now.addingTimeInterval(60)
    while !shop.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(shop.isBuilt)
    let clashes = FlushFaces.clashes(
      under: [shop.root], seenFrom: eyes(ShopLayout.camera),
      skip: { $0.name == ShopStage.keeperName })
    #expect(clashes.isEmpty, "\(clashes)")
  }

  @Test func theDeskHasNoFlushFaces() async throws {
    let desk = DeskStage(kit: GenzKit(), cats: GenzCatSource())
    desk.start()
    defer { desk.setOnScreen(false) }
    let deadline = Date.now.addingTimeInterval(60)
    while !desk.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(desk.isBuilt)
    let clashes = FlushFaces.clashes(
      under: [desk.root], seenFrom: eyes(DeskLayout.camera),
      skip: { $0.name == DeskStage.catName })
    #expect(clashes.isEmpty, "\(clashes)")
  }

  @Test func theLensesKeepTheirDepthFine() {
    #expect(GenzRoom.nearClip >= 0.1)
    #expect(GenzRoom.farClip / GenzRoom.nearClip <= 1000)
    #expect(TabCamera.nearClip >= 0.1)
    #expect(TabCamera.farClip / TabCamera.nearClip <= 1000)
  }

  /// The check itself: a print flush with its frame is found, one standing proud of it is not.
  @Test func aFaceFlushWithAnotherOfAnotherColourIsFound() {
    let kit = GenzKit()
    let frame = kit.block(0, 0, 0, 1, 0.02, 1, kit.matte(GenzColour(0x111111)))
    let flush = kit.block(0.1, 0, 0.1, 0.8, 0.02, 0.8, kit.matte(GenzColour(0xEEEEEE)))
    let proud = kit.block(0.1, 0, 0.1, 0.8, 0.03, 0.8, kit.matte(GenzColour(0xEEEEEE)))
    let eye = GenzRoomPoint(0.5, 10, 0.5).scene
    #expect(FlushFaces.clashes(under: [frame, flush], seenFrom: [eye]).count == 1)
    #expect(FlushFaces.clashes(under: [frame, proud], seenFrom: [eye]).isEmpty)
    let same = kit.block(0.1, 0, 0.1, 0.8, 0.02, 0.8, kit.matte(GenzColour(0x111111)))
    #expect(FlushFaces.clashes(under: [frame, same], seenFrom: [eye]).isEmpty)
  }
}
