import Foundation
import Testing

@testable import FeatureHome

@MainActor @Suite struct StyledHomeTests {
  @Test func theNoteHomeOpensOnIsNotAnArrival() {
    var arrivals = NoteArrivals()
    let arrived = arrivals.update(UUID())
    #expect(!arrived)
  }

  @Test func aNewerNoteIsAnArrivalOnce() {
    var arrivals = NoteArrivals()
    let next = UUID()
    _ = arrivals.update(UUID())
    let first = arrivals.update(next)
    let again = arrivals.update(next)
    #expect(first)
    #expect(!again)
  }

  @Test func theFirstNoteAfterNoneIsAnArrival() {
    var arrivals = NoteArrivals()
    _ = arrivals.update(nil)
    let arrived = arrivals.update(UUID())
    #expect(arrived)
  }

  @Test func losingTheNoteIsNotAnArrival() {
    var arrivals = NoteArrivals()
    _ = arrivals.update(UUID())
    let arrived = arrivals.update(nil)
    #expect(!arrived)
  }
}
