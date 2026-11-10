import Foundation
import MoodInterface
import Testing
import Wire

@Suite struct MoodStoreTests {
  final class File {
    var saved: [String: MoodCheckIn]?
  }

  @Test func readsWhatWasSavedBefore() {
    let check = MoodCheckIn(mood: .happy, date: Date(timeIntervalSince1970: 100))
    let store = MoodStore(load: { ["M": check] }, save: { _ in })
    #expect(store.latest == ["M": check])
  }

  @Test func savesACheckInAndRefusesAnOlderOne() {
    let file = File()
    let store = MoodStore(load: { nil }, save: { file.saved = $0 })
    let newer = MoodCheckIn(mood: .busy, date: Date(timeIntervalSince1970: 200))
    let older = MoodCheckIn(mood: .sleepy, date: Date(timeIntervalSince1970: 100))
    #expect(store.take(newer, for: "M"))
    #expect(!store.take(older, for: "M"))
    #expect(file.saved == ["M": newer])
    #expect(store.take(older, for: "M", replacing: true))
    #expect(file.saved == ["M": older])
  }

  @Test func setCleansTheNote() {
    let file = File()
    let store = MoodStore(load: { nil }, save: { file.saved = $0 })
    store.set(.missing, note: "  hi  ", for: "M", at: Date(timeIntervalSince1970: 1))
    #expect(file.saved?["M"]?.note == "hi")
  }
}
