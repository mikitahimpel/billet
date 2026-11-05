import CoreGraphics
import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite("Room style in the Window Seat")
struct RoomStyleSceneTests {
  @Test func aFreeChoiceIsSharedAtOnceAndALockedOneIsTriedOnFirst() {
    var choice = RoomStyleChoice(style: .standard)
    #expect(choice.tap(.wall(.sage), unlocked: true) == RoomStyle(wall: .sage))
    #expect(choice.trying == nil)
    #expect(choice.tap(.floor(.herringbone), unlocked: false) == nil)
    #expect(choice.trying == .floor(.herringbone))
    #expect(choice.shown.floor == .herringbone)
    #expect(choice.style.floor == .standard)
    #expect(choice.keep() == RoomStyle(wall: .sage, floor: .herringbone))
    #expect(choice.trying == nil)
  }

  @Test func choosingSomethingFreeDropsWhatWasTriedOn() {
    var choice = RoomStyleChoice(style: .standard, trying: .fairy(.ice))
    #expect(choice.tap(.wall(.rose), unlocked: true)?.fairy == .standard)
    #expect(choice.trying == nil)
    #expect(choice.tap(.wall(.rose), unlocked: true) == nil)
  }

  @Test func everyPatternIsSmallAndTilesItsColour() throws {
    var patterns: [GenzStylePattern] = RoomWall.allCases.filter(\.isWallpaper).map { .wall($0) }
    patterns += [RoomFloor.lightWood, .darkWood, .herringbone, .tiles].map { .floor($0) }
    patterns.append(.gingham(0xF4ECE0, 0xC2464A))
    for pattern in patterns {
      let image = try #require(pattern.image(), "\(pattern)")
      #expect(image.width == GenzStylePattern.size && image.height == GenzStylePattern.size)
      #expect(image.width <= 512)
      #expect(Self.edgesMatch(image), "\(pattern) shows a seam")
    }
    #expect(GenzStylePattern.wall(.sage).image() == nil)
    #expect(GenzStylePattern.floor(.plain).image() == nil)
  }

  /// Whether the left and right columns, and the top and bottom rows, are close in colour on
  /// average, as they are where a pattern runs on across its edge.
  private static func edgesMatch(_ image: CGImage) -> Bool {
    let size = image.width
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    let context = CGContext(
      data: &bytes, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    context?.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    func pixel(_ x: Int, _ y: Int) -> SIMD3<Float> {
      let index = (y * size + x) * 4
      return SIMD3(Float(bytes[index]), Float(bytes[index + 1]), Float(bytes[index + 2]))
    }
    var across: Float = 0
    var inside: Float = 0
    for step in 0..<size {
      across += simd_length(pixel(0, step) - pixel(size - 1, step))
      across += simd_length(pixel(step, 0) - pixel(step, size - 1))
      inside += simd_length(pixel(size / 2, step) - pixel(size / 2 - 1, step))
      inside += simd_length(pixel(step, size / 2) - pixel(step, size / 2 - 1))
    }
    return across <= max(inside * 2.5, Float(size) * 12)
  }

  @Test func closedCurtainsCoverTheWindowAndOpenOnesKeepClearOfTheSwitch() {
    let window = GenzLayout.Seat.window
    let closed = GenzRoomStyler.panelSpans(cover: 1)
    #expect(closed.left.lowerBound <= window.x0)
    #expect(closed.right.upperBound >= window.x1)
    #expect(closed.left.upperBound > closed.right.lowerBound + 0.05)
    let open = GenzRoomStyler.panelSpans(cover: Float(CurtainDrape.open.cover))
    let plateRight = GenzLightSwitch.plate.x + GenzLightSwitch.plateSize.x / 2
    #expect(open.left.lowerBound > plateRight)
    #expect(open.left.upperBound < window.x0 + 1)
    #expect(open.right.lowerBound > window.x1 - 1)
    let half = GenzRoomStyler.panelSpans(cover: Float(CurtainDrape.half.cover))
    #expect(half.left.upperBound < half.right.lowerBound)
    #expect(half.left.upperBound > open.left.upperBound)
  }

  @Test func theNoteHangsInFrontOfTheCurtainsInEverySet() {
    let front = GenzRoomStyler.curtainY + GenzRoomStyler.pleatDepth / 2
    let glass = -GenzLayout.Seat.wall / 2
    for furniture in RoomFurniture.allCases {
      #expect(GenzLayout.of(furniture).note.centre.y > front + 0.005, "\(furniture)")
    }
    #expect(GenzRoomStyler.curtainY - GenzRoomStyler.pleatDepth / 2 > glass - 0.01)
  }

  @Test func theStandardStyleDrawsOnlyTheFloor() {
    let styler = GenzRoomStyler(kit: GenzKit())
    styler.apply(.standard, animated: false)
    #expect(styler.root.children.filter(\.isEnabled).map(\.name) == [GenzRoomStyler.floorName])
    styler.apply(RoomStyle(wall: .sage, curtains: .rose), animated: false)
    let shown = Set(styler.root.children.filter(\.isEnabled).map(\.name))
    #expect(
      shown == [
        GenzRoomStyler.wallName, GenzRoomStyler.sideName, GenzRoomStyler.floorName,
        GenzRoomStyler.curtainName,
      ])
  }

  @Test func theCurtainsDrawAcrossOverAMomentWhenAnimated() {
    let styler = GenzRoomStyler(kit: GenzKit())
    styler.apply(RoomStyle(curtains: .linen), animated: false)
    #expect(styler.cover == Float(CurtainDrape.open.cover))
    styler.apply(RoomStyle(curtains: .linen, drape: .closed), animated: true)
    styler.step(GenzRoomStyler.drawLength / 2)
    #expect(styler.cover > Float(CurtainDrape.open.cover) && styler.cover < 1)
    styler.step(GenzRoomStyler.drawLength)
    #expect(styler.cover == 1)
  }

  @Test func theSkinsAreOneFlatMeshEachLaidInRoomUnits() {
    #expect(GenzRoomStyler.backWall().contents.models.count == 1)
    var mesh = GenzUVMesh()
    mesh.quad([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]) { SIMD2($0.x, $0.y) }
    #expect(mesh.triangleCount == 2)
  }

  @Test func theFairyLightsTakeTheStylesColourAndWarmKeepsThePresets() {
    let preset = LightingLook.cosy
    #expect(preset.tinted(.warm) == preset)
    let ice = preset.tinted(.ice)
    #expect(ice.fairy.colour == FairyColour.ice.rgb)
    #expect(ice.fairy.shown == preset.fairy.shown)
    #expect(ice.key == preset.key)
  }

  @Test func aRoomKeepsTheStyleItIsGivenBeforeItIsBuilt() {
    let room = GenzRoomCache(suite: "room-style-\(UUID())").room(GenzLayout.of(.original))
    let style = RoomStyle(wall: .butter, fairy: .rose)
    room.setStyle(style, animated: false)
    #expect(room.style == style)
    #expect(room.look.fairy.colour == FairyColour.rose.rgb || !room.look.fairy.shown)
  }
}
