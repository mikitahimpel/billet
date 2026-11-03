import CoreGraphics
import Foundation
import Pet
import Testing

@testable import PetSceneReality

@Suite("Scene touch routing")
struct CatTouchSceneTests {
  @Test func aDoubleTapIsTwoQuickTapsOnTheSameThing() {
    let first = CatTap(target: .floor, location: CGPoint(x: 100, y: 400), time: 10)
    #expect(first.isPartner(of: .floor, at: CGPoint(x: 110, y: 405), 10.2))
    #expect(!first.isPartner(of: .floor, at: CGPoint(x: 110, y: 405), 10.6))
    #expect(!first.isPartner(of: .cat, at: CGPoint(x: 110, y: 405), 10.2))
    #expect(!first.isPartner(of: .floor, at: CGPoint(x: 300, y: 405), 10.2))
  }

  @Test func nookiDragsFromItsToysAndBowl() {
    #expect(NookiDrag.of(.bowl) == .treat)
    #expect(NookiDrag.of(.toy(.wand)) == .decided(.wand))
    #expect(NookiDrag.of(.toy(.ball)) == .decided(.ball))
    // Nooki's own yarn keeps its own flick.
    #expect(NookiDrag.of(.toy(.yarn)) == .decided(nil))
    #expect(NookiDrag.of(.cat) == .decided(nil))
    #expect(NookiDrag.of(.nothing) == .decided(nil))
  }

  @MainActor @Test func everyToyHasAModel() {
    let toys = CatToyModels.make(length: 1)
    #expect(Set(toys.keys) == Set(CatToy.allCases))
    #expect(toys[.wand]?.findEntity(named: "feather") != nil)
  }
}
