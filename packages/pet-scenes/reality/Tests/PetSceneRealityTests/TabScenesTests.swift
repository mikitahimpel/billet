import Foundation
import Pet
import PetScene
import RealityKit
import Testing

@testable import PetSceneReality

struct ShopLayoutTests {
  private let slots = ShopLayout.slots(for: ShopCatalog.standard.items)

  @Test func everyItemInTheCatalogHasAPlace() {
    #expect(Set(slots.map(\.item)) == Set(ShopCatalog.standard.items.map(\.id)))
    #expect(slots.count == ShopCatalog.standard.items.count)
  }

  @Test func furnitureStandsOnShelvesTreatsOnTheCounterPaintsOnTheTable() {
    let catalog = ShopCatalog.standard
    for slot in slots {
      let item = catalog.item(slot.item)
      switch item?.category {
      case .furniture: #expect(slot.stand == .shelf)
      case .treats: #expect(slot.stand == .counter)
      case .materials: #expect(slot.stand == .table)
      case nil: Issue.record("unknown item \(slot.item)")
      }
    }
  }

  @Test func noTwoPlacesOverlap() {
    for (index, a) in slots.enumerated() {
      for b in slots.dropFirst(index + 1) where a.stand == b.stand && a.centre.z == b.centre.z {
        let apart = abs(a.centre.x - b.centre.x) >= (a.box.x + b.box.x) / 2 - 0.001
          || abs(a.centre.y - b.centre.y) >= (a.box.z + b.box.z) / 2 - 0.001
        #expect(apart, "\(a.item) and \(b.item)")
      }
    }
  }

  @Test func shelfPlacesStayInsideTheirBayAndUnderTheShelfAbove() {
    for slot in slots where slot.stand == .shelf {
      let inBay = ShopLayout.bays.contains {
        slot.centre.x - slot.box.x / 2 >= $0 && slot.centre.x + slot.box.x / 2 <= $0 + ShopLayout.bayWidth
      }
      #expect(inBay, "\(slot.item)")
      #expect(slot.box.y < ShopLayout.shelfGap)
    }
  }

  @Test func theKeeperStandsBetweenTheBaysBehindTheCounter() {
    let keeper = ShopLayout.keeper
    #expect(keeper.x > ShopLayout.bays[0] + ShopLayout.bayWidth)
    #expect(keeper.x < ShopLayout.bays[1])
    #expect(keeper.y > ShopLayout.shelfDepth && keeper.y < ShopLayout.counter.y0)
  }

  @Test func aLongCatalogPutsMoreToAShelfButNeverOverflows() {
    let many = (0..<40).map {
      ShopItem(
        id: "piece-\($0)", name: "Piece", price: 1,
        look: .furniture(model: "Item_yarn", fit: .width, size: 0.1, mount: .floor))
    }
    let placed = ShopLayout.slots(for: many)
    #expect(placed.count == ShopLayout.bays.count * ShopLayout.shelves.count * 3)
    #expect(placed.allSatisfy { $0.box.x > 0 })
  }

  @Test func scaleIsTrueToLifeWithinTheBoxAndNeverTiny() {
    let box = SIMD3<Float>(1, 1, 1)
    // Small enough to show at life size.
    #expect(ShopLayout.scale(extents: [0.4, 0.3, 0.4], box: box, unitsPerMetre: 1.7, least: 0.5) == 1.7)
    // Too big for the box: fitted.
    #expect(abs(ShopLayout.scale(extents: [0.2, 2, 0.2], box: box, unitsPerMetre: 1.7, least: 0.5) - 0.5) < 1e-5)
    // Tiny: grown until its longest side is `least`.
    let mouse = ShopLayout.scale(extents: [0.05, 0.07, 0.1], box: box, unitsPerMetre: 1.7, least: 0.5)
    #expect(abs(mouse * 0.1 - 0.5) < 1e-5)
  }

  @Test func aRugLiesFlatAndALampDoesNot() {
    #expect(ShopLayout.liesFlat([0.6, 0.02, 0.6]))
    #expect(!ShopLayout.liesFlat([0.2, 0.46, 0.2]))
  }
}

struct KeeperMotionTests {
  private let ahead = SIMD2<Float>(0, 0)

  @Test func aWaveLiftsTheRightArmAndEnds() {
    var motion = KeeperMotion(seed: 1)
    motion.wave()
    var highest: Float = 0
    var steps = 0
    while motion.isBusy, steps < 1000 {
      let pose = motion.step(1 / 60, viewer: ahead)
      highest = max(highest, pose.rightArm)
      #expect(pose.leftArm == KeeperMotion.restingArm)
      steps += 1
    }
    #expect(highest > 2)
    #expect(Double(steps) / 60 <= KeeperMotion.waveLength + 0.05)
    #expect(motion.step(1 / 60, viewer: ahead).rightArm == KeeperMotion.restingArm)
  }

  @Test func aCheerCutsInOnAWaveAndHops() {
    var motion = KeeperMotion(seed: 2)
    motion.wave()
    _ = motion.step(0.5, viewer: ahead)
    motion.cheer()
    var hopped = false
    var arms: Float = 0
    for _ in 0..<60 {
      let pose = motion.step(1 / 60, viewer: ahead)
      hopped = hopped || pose.hop > 0.05
      arms = max(arms, min(pose.leftArm, pose.rightArm))
    }
    #expect(hopped)
    #expect(arms > 1.5)
  }

  @Test func reducedMotionNeverHops() {
    var motion = KeeperMotion(seed: 3)
    motion.cheer()
    for _ in 0..<120 {
      let pose = motion.step(1 / 60, viewer: ahead, still: true)
      #expect(pose.hop == 0)
      #expect(pose.breath == 0)
    }
  }

  @Test func theHeadFollowsTheViewerButNotOverItsShoulder() {
    var motion = KeeperMotion(seed: 4)
    var pose = KeeperPose()
    for _ in 0..<240 { pose = motion.step(1 / 60, viewer: [2, 1]) }
    #expect(abs(pose.headYaw - KeeperMotion.headYawLimit) < 0.01)
    #expect(abs(pose.headPitch - KeeperMotion.headPitchLimit) < 0.01)
  }

  @Test func aGlanceTurnsTheHeadAwayThenBack() {
    var motion = KeeperMotion(seed: 5)
    motion.glance(yaw: -1, pitch: 0.2)
    var pose = KeeperPose()
    for _ in 0..<60 { pose = motion.step(1 / 60, viewer: ahead) }
    #expect(pose.headYaw < -0.8)
    for _ in 0..<240 { pose = motion.step(1 / 60, viewer: ahead) }
    #expect(abs(pose.headYaw) < 0.05)
  }

  @Test func itBlinks() {
    var motion = KeeperMotion(seed: 6)
    var shut = false
    for _ in 0..<(60 * 8) { shut = shut || motion.step(1 / 60, viewer: ahead).blink > 0.9 }
    #expect(shut)
  }

  @Test func aimPointsTheFaceAtTheOffset() {
    let right = KeeperMotion.aim(at: [1, 0, 1])
    #expect(abs(right.x - .pi / 4) < 1e-5)
    #expect(abs(right.y) < 1e-5)
    let above = KeeperMotion.aim(at: [0, 1, 1])
    #expect(abs(above.y - .pi / 4) < 1e-5)
  }

  @Test func theEnvelopeRisesHoldsAndFalls() {
    #expect(KeeperMotion.envelope(0, rise: 0.5, fall: 0.5, length: 2) == 0)
    #expect(KeeperMotion.envelope(1, rise: 0.5, fall: 0.5, length: 2) == 1)
    #expect(KeeperMotion.envelope(2, rise: 0.5, fall: 0.5, length: 2) == 0)
  }
}

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
        #expect(abs(a.centre.x - b.centre.x) >= gap * 0.9 || abs(a.centre.z - b.centre.z) >= gap * 0.9)
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
    #expect(stages.shopStage === stages.shopStage)
    #expect(stages.deskStage === stages.deskStage)
  }

  @Test(arguments: Shopkeeper.allCases)
  func everyKeeperShipsWithItsJoints(_ keeper: Shopkeeper) async throws {
    let model = try #require(await KeeperRig.load(keeper))
    let rig = try #require(KeeperRig(model: model))
    for joint in KeeperRig.joints {
      #expect(model.findEntity(named: joint) != nil, "\(keeper) lacks \(joint)")
    }
    rig.apply(KeeperPose(hop: 0.1, headYaw: 0.5, rightArm: 2))
    #expect(rig.head != nil)
  }

  @Test func theStreetOutsideTheShopIsDrawn() {
    #expect(ShopArt.street() != nil)
  }

  @Test func theNookiSceneHasBothTabScenes() {
    let scene = NookiPetScene()
    #expect(scene.makeShopScene(state: ShopSceneState(items: []), onEvent: { _ in }) != nil)
    #expect(scene.makeDeskScene(state: DeskSceneState(notes: []), onEvent: { _ in }) != nil)
  }
}
