import Foundation
import Testing

@testable import FeatureGames

@Suite struct FeedAftermathTests {
  @Test func rightAmountNeverLoafs() {
    var after = FeedAftermath(stuffed: false)
    for _ in 0..<100 { #expect(after.advance(0.1).isEmpty) }
    #expect(!after.loafed)
  }

  @Test func stuffedCatEatsThenLoafsAndYawnsOnce() {
    var after = FeedAftermath(stuffed: true)
    #expect(after.advance(2.4).isEmpty)
    #expect(after.advance(0.2) == [.loaf, .yawn])
    #expect(after.loafed)
    var later: [FeedAftermath.Act] = []
    for _ in 0..<20 { later += after.advance(0.1) }
    #expect(!later.contains(.loaf))
    #expect(!later.contains(.yawn))
  }

  @Test func stuffedCatBlinksSlowlyEveryFewSeconds() {
    var after = FeedAftermath(stuffed: true)
    var blinks = 0
    for _ in 0..<100 { blinks += after.advance(0.1).filter { $0 == .slowBlink }.count }
    #expect(blinks >= 2)
  }

  @Test func negativeTimeDoesNotRewind() {
    var after = FeedAftermath(stuffed: true)
    _ = after.advance(3)
    _ = after.advance(-5)
    #expect(after.time == 3)
  }

  @Test func onScreenRules() {
    let size = CGSize(width: 390, height: 844)
    #expect(OnScreen.contains(CGPoint(x: 195, y: 400), in: size))
    #expect(!OnScreen.contains(nil, in: size))
    #expect(!OnScreen.contains(CGPoint(x: -1, y: 400), in: size))
    #expect(!OnScreen.contains(CGPoint(x: 195, y: 900), in: size))
    #expect(!OnScreen.contains(CGPoint(x: 5, y: 400), in: size, inset: 20))
    #expect(!OnScreen.contains(CGPoint(x: 5, y: 5), in: .zero))
  }
}
