import DecorInterface
import RealityKit
import RoomInterface
import Testing

@testable import Billet

@MainActor
struct BedroomPlacementTests {
    private func stage() -> DecorStage { DecorStage(space: .bedroom, build: BedroomFurniture.build) }

    private func holders(_ stage: DecorStage) -> [String: Entity] {
        Dictionary(uniqueKeysWithValues: stage.root.children.filter { $0.name.hasPrefix("decor.") }.map { ($0.name, $0) })
    }

    @Test func theStageStandsTheBedroomsNineOwnPiecesAndNothingOfTheLivingRoom() {
        let bedroom = stage()
        bedroom.apply(RoomDecor(), receiver: nil)
        let names = Set(holders(bedroom).keys)
        #expect(names == Set(DecorItem.baseItems(in: .bedroom).map { "decor.\($0.id)" }))
        let living = DecorStage()
        living.apply(RoomDecor(), receiver: nil)
        #expect(holders(living).keys.allSatisfy { !$0.hasPrefix("decor.base-bedroom-") })
    }

    @Test func aPieceStandsWhereTheLayoutPutsIt() throws {
        let bedroom = stage()
        let moved = Placement(item: "base-bedroom-bed", surface: .floor, u: 2, v: -3, quarterTurns: 1, space: .bedroom)
        bedroom.apply(RoomDecor(layout: DecorLayout().putting(moved)), receiver: nil)
        let bed = try #require(holders(bedroom)["decor.base-bedroom-bed"])
        #expect(abs(bed.position.x - 0.1) < 0.001 && abs(bed.position.z + 0.15) < 0.001)
        #expect(abs(bed.orientation.angle - .pi / 2) < 0.001)
    }

    @Test func aMovePlateIsMadeOnlyForTheChosenPieceAndHiddenAgain() {
        let bedroom = stage()
        bedroom.apply(RoomDecor(), receiver: nil)
        let before = Self.count(bedroom.root)
        bedroom.apply(RoomDecor(mode: .arranging(selected: "base-bedroom-bed", fits: true)), receiver: nil)
        #expect(Self.count(bedroom.root) == before + 1)
        bedroom.apply(RoomDecor(), receiver: nil)
        #expect(Self.count(bedroom.root) == before + 1)
        #expect(Self.enabledModels(bedroom.root) == Self.enabledModels(Self.fresh()) )
    }

    private static func fresh() -> Entity {
        let bedroom = DecorStage(space: .bedroom, build: BedroomFurniture.build)
        bedroom.apply(RoomDecor(), receiver: nil)
        return bedroom.root
    }

    private static func count(_ entity: Entity) -> Int { 1 + entity.children.reduce(0) { $0 + count($1) } }

    private static func enabledModels(_ entity: Entity) -> Int {
        guard entity.isEnabled else { return 0 }
        return (entity.components.has(ModelComponent.self) ? 1 : 0) + entity.children.reduce(0) { $0 + enabledModels($1) }
    }

    @Test func theCatLivesOnTheSillAndWalksOutToHerBedByDefault() {
        let plan = CityRoomScene.catPlan(DecorLayout(), sillTop: 0.2925)
        #expect(plan.home == [0.25, 0.2925, -0.44])
        #expect(plan.route.count == 5)
        #expect(plan.main?.path.count == 4)
        // The way out ends on her bed's seat.
        let end = plan.main?.path.last?.at
        #expect(end != nil && abs(end!.x - 0.25) < 0.001 && abs(end!.z - 0.30) < 0.001)
    }

    @Test func movingTheBedAwayFromTheSillLetsHerLiveInHerOwnBed() {
        let far = Placement(item: "base-bedroom-bed", surface: .floor, u: 0, v: 7, space: .bedroom)
        let plan = CityRoomScene.catPlan(DecorLayout().putting(far), sillTop: 0.2925)
        #expect(plan.home != [0.25, 0.2925, -0.44])
        #expect(plan.main == nil)
    }

    @Test func herWayFollowsTheBedAndHerOwnBed() {
        let moved = DecorLayout()
            .putting(Placement(item: "base-bedroom-bed", surface: .floor, u: 4, v: -3, space: .bedroom))
            .putting(Placement(item: "base-bedroom-catbed", surface: .floor, u: -2, v: 6, space: .bedroom))
        let plan = CityRoomScene.catPlan(moved, sillTop: 0.2925)
        #expect(plan.home == [0.25, 0.2925, -0.44])
        let seat = plan.main?.path.last?.at
        #expect(seat != nil && abs(seat!.x + 0.1) < 0.001)
        let stored = CityRoomScene.catPlan(DecorLayout().storing("base-bedroom-catbed"), sillTop: 0.2925)
        #expect(stored.main?.path.count == 2)
    }

    @Test func theBedroomsFurnitureDoesNotCountAgainstTheCapOfBoughtPieces() {
        let owned = Set(DecorItem.all.filter { !$0.isBase }.prefix(12).map(\.id))
        let settled = DecorLayout(stored: []).settled(owned: owned)
        #expect(settled.placements.filter { DecorItem.item(shopID: $0.item)?.isBase == false }.count <= DecorLayout.maxPlaced)
        #expect(settled.allPlacements(in: .bedroom).count == 9)
    }
}
