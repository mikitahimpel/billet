import Foundation
import Testing

@testable import FeatureHome

@MainActor @Suite struct StyledHomeTests {
  @Test func theNoteHomeOpensOnIsNotAnArrival() {
    var arrivals = NoteArrivals()
    #expect(!arrivals.update(UUID()))
  }

  @Test func aNewerNoteIsAnArrivalOnce() {
    var arrivals = NoteArrivals()
    let first = UUID()
    let next = UUID()
    _ = arrivals.update(first)
    #expect(arrivals.update(next))
    #expect(!arrivals.update(next))
  }

  @Test func theFirstNoteAfterNoneIsAnArrival() {
    var arrivals = NoteArrivals()
    _ = arrivals.update(nil)
    #expect(arrivals.update(UUID()))
  }

  @Test func losingTheNoteIsNotAnArrival() {
    var arrivals = NoteArrivals()
    _ = arrivals.update(UUID())
    #expect(!arrivals.update(nil))
  }
}
