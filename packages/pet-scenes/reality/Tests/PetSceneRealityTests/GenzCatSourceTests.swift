import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
struct GenzCatSourceTests {
  @Test func onlyTheCatsSomeoneHoldsStayLoaded() async {
    let source = GenzCatSource()
    let room = NSObject()
    let adoption = NSObject()
    let kitten = CatChoice(model: .detailedKitten)
    let fluffy = CatChoice(model: .detailedFluffy)

    source.hold([.standard], for: room)
    _ = await source.cat(.standard)
    source.hold([kitten, fluffy, .standard], for: adoption)
    _ = await source.cat(kitten)
    _ = await source.cat(fluffy)
    let standard = CatChoice.standard.model
    #expect(source.loaded == [standard, .detailedKitten, .detailedFluffy])

    source.hold([], for: adoption)
    #expect(source.loaded == [standard], "the room's cat stays when the adoption lets go")

    source.hold([kitten], for: room)
    #expect(source.loaded.isEmpty, "a cat nobody holds any more is let go")
  }

  @Test func aPlacedCatStaysWhenItsModelIsLetGo() async throws {
    let source = GenzCatSource()
    let owner = NSObject()
    source.hold([.standard], for: owner)
    let (cat, _) = try #require(await source.cat(.standard))
    source.hold([], for: owner)
    #expect(source.loaded.isEmpty)
    #expect(!cat.visualBounds(relativeTo: nil).isEmpty)
  }
}

@MainActor
struct GenzRoomCacheReleaseTests {
  @Test func aRoomLeftForAnotherIsLetGoAndBuiltAfreshIfAskedAgain() {
    let rooms = GenzRoomCache(suite: "genz-release-\(UUID())")
    let nook = GenzLayout.of(.cosyNook)
    let first = rooms.room(nook)
    first.setOnScreen(true, in: UUID())
    rooms.release(nook.key)
    #expect(rooms.room(nook) === first, "a room still shown is kept")

    let view = UUID()
    let shown = rooms.room(GenzLayout.of(.retroDen))
    shown.setOnScreen(true, in: view)
    shown.setOnScreen(false, in: view)
    rooms.release(GenzLayout.of(.retroDen).key)
    #expect(rooms.room(GenzLayout.of(.retroDen)) !== shown)
  }
}
