import Foundation
import RealityKit
import Testing
import simd

@testable import PetSceneReality

@Suite struct NookiLayoutTests {
  private func plan() -> NookiFloorPlan {
    NookiFloorPlan(
      homes: [
        "chair": .init(centre: [0.4, -0.4], half: [0.15, 0.15]),
        "table": .init(centre: [0.5, 0.4], half: [0.1, 0.1]),
      ],
      fixed: [.init(centre: [0, 0], half: [0.2, 0.2])])
  }

  @Test func pointsSnapToTheNearestCell() {
    #expect(
      NookiFloorPlan.nearestCell(to: [0.26, -0.14]) == NookiLayout.Cell(column: 3, row: -1))
    #expect(NookiFloorPlan.centre(of: .init(column: 3, row: -1)) == [0.3, -0.1] * 1.0 + [0, 0])
  }

  @Test func aPieceTakesAFreeCell() {
    #expect(
      plan().cell(for: "chair", nearest: [0.42, 0.12], in: NookiLayout())
        == .init(column: 4, row: 1))
  }

  @Test func aPieceCantLeaveTheRoom() {
    #expect(plan().cell(for: "chair", nearest: [0.9, 0], in: NookiLayout()) == nil)
    #expect(plan().cell(for: "chair", nearest: [-0.6, 0], in: NookiLayout()) == nil)
  }

  @Test func aPieceCantStandOnAnother() {
    #expect(plan().cell(for: "chair", nearest: [0.5, 0.4], in: NookiLayout()) == nil)
  }

  @Test func aPieceCantStandOnSomethingFixed() {
    #expect(plan().cell(for: "table", nearest: [0.1, 0.1], in: NookiLayout()) == nil)
  }

  @Test func aPieceDoesntBlockItself() {
    #expect(plan().cell(for: "chair", nearest: [0.4, -0.4], in: NookiLayout()) != nil)
  }

  @Test func overlapFollowsWhereAMovedPieceNowStands() {
    var layout = NookiLayout()
    layout.pieces["table"] = .init(column: -4, row: -4)
    #expect(plan().cell(for: "chair", nearest: [-0.4, -0.4], in: layout) == nil)
    #expect(plan().cell(for: "chair", nearest: [0.5, 0.4], in: layout) != nil)
  }

  @Test func anUnknownPieceHasNowhereToGo() {
    #expect(plan().cell(for: "piano", nearest: [0.4, 0.4], in: NookiLayout()) == nil)
  }

  @Test func theLayoutRoundTripsAndStaysFrameSized() throws {
    var layout = NookiLayout(wall: .moss, floor: .cocoa)
    for name in ["Item_bookcase", "Item_monstera", "Item_armchair", "Item_lamp", "Item_teatable"] {
      layout.pieces[name] = .init(column: -5, row: 6)
    }
    layout.pieces["Item_tower"] = .init(column: 6, row: -5)
    let data = try JSONEncoder().encode(layout)
    #expect(try JSONDecoder().decode(NookiLayout.self, from: data) == layout)
    #expect(data.count < 512)
  }

  @Test func theStoreKeepsALayoutAndSurvivesRubbish() throws {
    let defaults = try #require(UserDefaults(suiteName: "nooki-layout-\(UUID())"))
    let store = NookiLayoutStore(defaults: defaults)
    #expect(store.load() == NookiLayout())
    store.save(NookiLayout(wall: .clay))
    #expect(store.load().wall == .clay)
    defaults.set(Data("rubbish".utf8), forKey: "nooki.layout")
    #expect(store.load() == NookiLayout())
  }

  @Test func thereAreAboutSixPaintsAllWarmEnoughToTell() {
    #expect(NookiSwatch.allCases.count == 6)
    #expect(Set(NookiSwatch.allCases.map(\.rgb)).count == 6)
  }

  @Test func aScreenPointFindsItsFloorPoint() throws {
    let camera = NookiCamera().position
    let point = try #require(
      NookiFloorRay.floorPoint(
        under: [201, 437], viewSize: [402, 874], camera: camera, target: NookiCamera.target,
        verticalFieldOfView: 30))
    let ahead = simd_normalize(NookiCamera.target - camera)
    let landing = camera + ahead * (-camera.y / ahead.y)
    #expect(simd_distance(point, SIMD2(landing.x, landing.z)) < 0.001)
  }

  @Test func theFloorRayMatchesWhereTheBallIsDrawn() throws {
    let point = try #require(
      NookiFloorRay.floorPoint(
        under: [184, 548], viewSize: [402, 874], camera: NookiCamera().position,
        target: NookiCamera.target, verticalFieldOfView: 30, height: 0.07))
    #expect(simd_distance(point, [0.36, 0.54]) < 0.1)
  }

  @Test func aRayAboveTheHorizonFindsNoFloor() {
    let point = NookiFloorRay.floorPoint(
      under: [100, 0], viewSize: [100, 100], camera: [0, 1, 10], target: [0, 8, 0],
      verticalFieldOfView: 30)
    #expect(point == nil)
  }
}

@MainActor @Suite struct NookiRenovationTests {
  private func make() throws -> (NookiRenovation, Entity, Entity, NookiLayoutStore) {
    let defaults = try #require(UserDefaults(suiteName: "nooki-renovation-\(UUID())"))
    let store = NookiLayoutStore(defaults: defaults)
    let renovation = NookiRenovation(store: store)
    let chair = Entity()
    chair.position = [0.4, 0, -0.4]
    let table = Entity()
    table.position = [0.5, 0, 0.4]
    renovation.register("chair", holder: chair, half: [0.1, 0.1])
    renovation.register("table", holder: table, half: [0.1, 0.1])
    renovation.isOn = true
    return (renovation, chair, table, store)
  }

  @Test func onlyRegisteredEntitiesArePieces() throws {
    let (renovation, chair, _, _) = try make()
    #expect(renovation.isPiece(chair))
    #expect(!renovation.isPiece(Entity()))
  }

  @Test func nothingLiftsWhileTheRoomIsClosed() throws {
    let (renovation, chair, _, _) = try make()
    renovation.isOn = false
    #expect(!renovation.lift(chair))
  }

  @Test func aDragSnapsThePieceAndADropSavesIt() throws {
    let (renovation, chair, _, store) = try make()
    #expect(renovation.lift(chair))
    renovation.move(towards: [0.03, -0.42])
    #expect(simd_distance(chair.position, [0, chair.position.y, -0.4]) < 0.0001)
    #expect(store.load().pieces.isEmpty)
    #expect(renovation.drop() != nil)
    #expect(store.load().pieces["chair"] == .init(column: 0, row: -4))
  }

  @Test func aTakenCellLeavesThePieceWhereItWas() throws {
    let (renovation, chair, _, _) = try make()
    _ = renovation.lift(chair)
    renovation.move(towards: [0.5, 0.4])
    #expect(simd_distance(chair.position, [0.4, chair.position.y, -0.4]) < 0.0001)
  }

  @Test func aLiftedPieceRisesAndSettlesBackToTheFloor() throws {
    let (renovation, chair, _, _) = try make()
    _ = renovation.lift(chair)
    for _ in 0..<30 { renovation.step(1.0 / 60, reduceMotion: false) }
    #expect(chair.position.y > 0.05)
    _ = renovation.drop()
    for _ in 0..<60 { renovation.step(1.0 / 60, reduceMotion: false) }
    #expect(chair.position.y == 0)
    #expect(!renovation.isMoving)
  }

  @Test func resetPutsEverythingBack() throws {
    let (renovation, chair, _, store) = try make()
    _ = renovation.lift(chair)
    renovation.move(towards: [0, -0.4])
    _ = renovation.drop()
    renovation.reset(reduceMotion: true)
    #expect(simd_distance(chair.position, [0.4, chair.position.y, -0.4]) < 0.0001)
    #expect(store.load() == NookiLayout())
  }

  @Test func aStoredLayoutIsWhereTheRoomOpens() throws {
    let defaults = try #require(UserDefaults(suiteName: "nooki-renovation-\(UUID())"))
    let store = NookiLayoutStore(defaults: defaults)
    store.save(NookiLayout(pieces: ["chair": .init(column: 1, row: -3)]))
    let renovation = NookiRenovation(store: store)
    let chair = Entity()
    chair.position = [0.4, 0, -0.4]
    renovation.register("chair", holder: chair, half: [0.1, 0.1])
    renovation.applyStored()
    #expect(simd_distance(chair.position, [0.1, 0, -0.3]) < 0.0001)
  }

  @Test func aBounceDiesAway() {
    #expect(NookiRenovation.bounce(0) > NookiRenovation.bounce(0.7))
    #expect(NookiRenovation.bounce(2) < 0.0001)
  }
}
