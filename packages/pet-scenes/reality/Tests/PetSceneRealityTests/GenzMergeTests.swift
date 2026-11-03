import Foundation
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
struct GenzMergeTests {
  private func kit() async -> GenzKit {
    let kit = GenzKit()
    await kit.makeTextures()
    return kit
  }

  private func models(_ piece: Entity) -> [ModelEntity] {
    piece.children.compactMap { $0 as? ModelEntity }
  }

  @Test func partsWithTheSameTextureJoinWithTheirRepeatsInTheirCoordinates() async throws {
    let kit = await kit()
    let colour = GenzColour(0x996633)
    let piece = Entity()
    let mesh = kit.box([1, 1, 1])
    let plainCoordinates = try #require(mesh.contents.models.first?.parts.first?.textureCoordinates)
    let widest = plainCoordinates.elements.map(\.x).max() ?? 0
    piece.addChild(kit.part(mesh, kit.matte(colour, .wood), at: [0, 0, 0]))
    piece.addChild(kit.part(mesh, kit.matte(colour, .wood, repeats: [3, 1]), at: [2, 0, 0]))
    kit.merge(piece, key: "test textured")

    let joined = try #require(models(piece).first)
    #expect(models(piece).count == 1)
    let material = try #require(joined.model?.materials.first as? PhysicallyBasedMaterial)
    #expect(material.baseColor.texture?.resource == kit.textures[.wood]?.colour)
    #expect(material.textureCoordinateTransform.scale == [1, 1])
    let part = try #require(joined.model?.mesh.contents.models.first?.parts.first)
    let coordinates = try #require(part.textureCoordinates).elements
    #expect(abs((coordinates.map(\.x).max() ?? 0) - widest * 3) < 1e-4)
  }

  @Test func differentTexturesAndColoursStayApart() async throws {
    let kit = await kit()
    let piece = Entity()
    let mesh = kit.box([1, 1, 1])
    piece.addChild(kit.part(mesh, kit.matte(GenzColour(0x996633), .wood)))
    piece.addChild(kit.part(mesh, kit.matte(GenzColour(0x996633), .knit)))
    piece.addChild(kit.part(mesh, kit.matte(GenzColour(0x336699), .wood)))
    kit.merge(piece, key: "test apart")
    #expect(models(piece).count == 3)
  }

  @Test func aTwoSidedPartNeverJoinsOneSidedOnes() async throws {
    let kit = await kit()
    let piece = Entity()
    let mesh = kit.box([1, 1, 1])
    var twoSided = kit.matte(GenzColour(0x996633), .knit)
    twoSided.faceCulling = .none
    piece.addChild(kit.part(mesh, kit.matte(GenzColour(0x996633), .knit)))
    piece.addChild(kit.part(mesh, kit.matte(GenzColour(0x996633), .knit), at: [2, 0, 0]))
    piece.addChild(kit.part(mesh, twoSided, at: [4, 0, 0]))
    kit.merge(piece, key: "test culling")
    let culled = models(piece).compactMap {
      ($0.model?.materials.first as? PhysicallyBasedMaterial)?.faceCulling
    }
    #expect(culled.count == 2)
    #expect(culled.contains(.none))
  }

  @Test func aTurnedTextureIsLeftAlone() async throws {
    let kit = await kit()
    let piece = Entity()
    let mesh = kit.box([1, 1, 1])
    var turned = kit.matte(GenzColour(0x996633), .wood)
    turned.textureCoordinateTransform.rotation = 0.5
    piece.addChild(kit.part(mesh, turned))
    piece.addChild(kit.part(mesh, turned, at: [2, 0, 0]))
    kit.merge(piece, key: "test turned")
    #expect(models(piece).count == 2)
  }
}
