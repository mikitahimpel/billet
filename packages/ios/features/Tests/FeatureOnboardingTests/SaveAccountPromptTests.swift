import Foundation
import Persistence
import Testing

@testable import FeatureOnboarding

@Suite struct SaveAccountPromptTests {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  let day: TimeInterval = 24 * 60 * 60

  @Test func waitsForAWeekOfUse() {
    let prompt = SaveAccountPrompt(startedAt: start)
    #expect(!prompt.isOffered(linked: false, notesSent: 0, now: start + 6 * day))
    #expect(prompt.isOffered(linked: false, notesSent: 0, now: start + 7 * day))
  }

  @Test func orForAFewNotes() {
    let prompt = SaveAccountPrompt(startedAt: start)
    #expect(!prompt.isOffered(linked: false, notesSent: 4, now: start + day))
    #expect(prompt.isOffered(linked: false, notesSent: 5, now: start + day))
  }

  @Test func neverForALinkedAccount() {
    let prompt = SaveAccountPrompt(startedAt: start)
    #expect(!prompt.isOffered(linked: true, notesSent: 50, now: start + 60 * day))
  }

  @Test func closingItHidesItForAMonth() {
    let prompt = SaveAccountPrompt(startedAt: start).dismissed(at: start + 8 * day)
    #expect(!prompt.isOffered(linked: false, notesSent: 9, now: start + 20 * day))
    #expect(prompt.isOffered(linked: false, notesSent: 9, now: start + 38 * day))
  }

  @Test func theStoreRemembersTheFirstDayAndTheDismissal() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SaveAccountPromptStore.storage(.directory(directory))
    let first = store.load(start)
    #expect(first == SaveAccountPrompt(startedAt: start))
    #expect(store.load(start + 3 * day) == first)
    store.save(first.dismissed(at: start + 9 * day))
    #expect(store.load(start + 10 * day).dismissedAt == start + 9 * day)
  }
}
