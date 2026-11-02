import Foundation
import Testing

@testable import PetSceneReality

private let view = UUID()

@MainActor
@Suite struct NookiRoomCacheTests {
  @Test func comingBackGetsTheSameRoom() {
    let cache = NookiRoomCache()
    #expect(cache.diorama() === cache.diorama())
  }

  @Test func aMemoryWarningLetsGoOfARoomOffScreen() {
    let cache = NookiRoomCache()
    let room = cache.diorama()
    room.setOnScreen(false, in: view)
    cache.purgeIfOffScreen()
    #expect(cache.diorama() !== room)
  }

  @Test func aMemoryWarningKeepsTheRoomOnScreen() {
    let cache = NookiRoomCache()
    let room = cache.diorama()
    room.setOnScreen(true, in: view)
    cache.purgeIfOffScreen()
    #expect(cache.diorama() === room)
  }

  @Test func aViewThatGoesLeavesTheRoomOnForTheViewThatReplacedIt() {
    let room = NookiDiorama()
    let old = UUID()
    let new = UUID()
    room.setOnScreen(true, in: old)
    room.setOnScreen(true, in: new)
    room.setOnScreen(false, in: old)
    #expect(room.isOnScreen)
    room.setOnScreen(false, in: new)
    #expect(!room.isOnScreen)
  }
}
