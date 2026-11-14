import DecorInterface
import RealityKit
import Testing

@testable import Billet

/// The nightstand's lamp shade on a phone: an emissive cylinder lit past the tone mapping's range is a flat white
/// blank, so its glow stays within what the Living room's lamp gives off.
@MainActor
struct BedroomLampTests {
    @Test func theLitShadeGlowsNoHarderThanTheLivingRoomsLamp() throws {
        let living = try #require(RoomPieces.glows.values.map(\.intensity).max())
        #expect(BedroomFurniture.shade(lamps: 1).emissiveIntensity <= living)
        #expect(BedroomFurniture.shade(lamps: 0).emissiveIntensity < BedroomFurniture.shade(lamps: 1).emissiveIntensity)
        #expect(BedroomFurniture.shade(lamps: 0).emissiveIntensity > 0)
    }

    @Test func theNightstandIsBuiltWithItsShadeOff() throws {
        let item = try #require(DecorItem.item(shopID: "base-bedroom-nightstand"))
        let nightstand = try #require(BedroomFurniture.build(item))
        let shade = try #require(nightstand.findEntity(named: BedroomFurniture.lampShade) as? ModelEntity)
        let material = try #require(shade.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(material.emissiveIntensity == BedroomFurniture.shade(lamps: 0).emissiveIntensity)
        #expect(nightstand.findEntity(named: BedroomFurniture.lampLight) != nil)
    }
}
