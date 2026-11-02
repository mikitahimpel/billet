import Testing

@testable import PetSceneReality

@MainActor
@Suite struct NookiRoomCacheTests {
  @Test func comingBackGetsTheSameRoom() {
    let cache = NookiRoomCache()
    #expect(cache.diorama() === cache.diorama())
  }

  @Test func aMemoryWarningLetsGoOfARoomOffScreen() {
    let cache = NookiRoomCache()
    let room = cache.diorama()
    room.setOnScreen(false)
    cache.purgeIfOffScreen()
    #expect(cache.diorama() !== room)
  }

  @Test func aMemoryWarningKeepsTheRoomOnScreen() {
    let cache = NookiRoomCache()
    let room = cache.diorama()
    room.setOnScreen(true)
    cache.purgeIfOffScreen()
    #expect(cache.diorama() === room)
  }

  @Test func theRoomsOwnViewWaitsForARehearsalToEnd() async {
    let cache = NookiRoomCache()
    await cache.untilRehearsed()
    cache.beginRehearsal()
    let waiting = Task { await cache.untilRehearsed() }
    await Task.yield()
    cache.endRehearsal()
    await waiting.value
  }
}
