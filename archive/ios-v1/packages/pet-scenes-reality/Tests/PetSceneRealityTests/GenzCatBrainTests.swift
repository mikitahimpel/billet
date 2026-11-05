import Foundation
import Pet
import PetScene
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzCatBrainTests {
  private func built(_ furniture: RoomFurniture) async throws -> GenzRoom {
    let layout = GenzLayout.of(furniture)
    let room = GenzRoom(
      layout: layout, kit: GenzKit(), cats: GenzCatSource(),
      spots: GenzSpotStore(defaults: UserDefaults(suiteName: "brain-\(UUID())")!, key: layout.key))
    room.startBuilding()
    let deadline = Date.now.addingTimeInterval(120)
    while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(room.isBuilt)
    return room
  }

  @Test func theWindowSeatOffersWhatItHas() async throws {
    let room = try await built(.cosyNook)
    let found = RoomAffordances(room.affordances().map(\.affordance))
    // On the seat: the window, the cardigan, the mugs and the phone, the bowl and the toys.
    for kind in [RoomAffordance.Kind.window, .soft, .smallItem, .bowl, .toy] {
      #expect(found.reachable(kind), "\(kind)")
    }
    // The cat bed is down on the rug: the cat jumps down off the seat to get to it.
    #expect(found.has(.bed))
    #expect(found.reachable(.bed))
    #expect(found.reachable(.rug))
    #expect(!found.has(.door))
    // Wherever it sends the cat there, its body keeps out of the pillows.
    try GenzCatObstacleTests.theBrainsTargetsAreClear(in: room)
  }

  @Test func everyPieceKindIsSorted() {
    // Each kind is either something the cat uses or deliberately nothing, so a new piece is
    // decided on rather than forgotten.
    let used = GenzPiece.Kind.allCases.filter { GenzRoom.affordanceKind($0) != nil }
    #expect(used.count >= 13)
    #expect(GenzRoom.affordanceKind(.cardigan) == .soft)
    #expect(GenzRoom.affordanceKind(.mugs) == .smallItem)
    #expect(GenzRoom.affordanceKind(.windowBench) == nil)
  }

  @Test func aFrameWaitsForTheCatToLoad() async throws {
    let room = try await built(.cosyNook)
    let frame = CatBrainFrame(
      stack: CatBrainStack(vitality: .awake, step: .watchWindow), action: .sit,
      target: .affordance(.window), gaze: .window, pace: 0, stepStart: 0, stepEnd: 30)
    room.followBrain(frame, speed: 600)
    // With no cat loaded the body waits; the frame is kept for when it comes.
    #expect(room.stepBrain(1 / 60) == nil || room.rig != nil)
    #expect(room.brainBody.frame == frame)
  }
}
