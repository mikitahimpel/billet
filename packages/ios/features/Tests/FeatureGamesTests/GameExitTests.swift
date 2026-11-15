import Foundation
import Testing

@testable import GamesInterface

@Suite struct GameExitTests {
  @Test(arguments: [
    (CGPoint(x: 200, y: 0), CGSize(width: 0, height: 300)),
    (CGPoint(x: 200, y: 139), CGSize(width: 40, height: 91)),
    (CGPoint(x: 20, y: 80), CGSize(width: -60, height: 200)),
  ])
  func aSwipeDownFromTheTopLeaves(start: CGPoint, translation: CGSize) {
    #expect(GameExit.isSwipe(from: start, translation: translation))
  }

  @Test(arguments: [
    (CGPoint(x: 200, y: 140), CGSize(width: 0, height: 300)),
    (CGPoint(x: 200, y: 400), CGSize(width: 0, height: 300)),
    (CGPoint(x: 200, y: 50), CGSize(width: 0, height: 90)),
    (CGPoint(x: 200, y: 50), CGSize(width: 0, height: -300)),
    (CGPoint(x: 200, y: 50), CGSize(width: 200, height: 150)),
    (CGPoint(x: 200, y: 50), CGSize(width: -150, height: 150)),
  ])
  func otherDragsStayInTheGame(start: CGPoint, translation: CGSize) {
    #expect(!GameExit.isSwipe(from: start, translation: translation))
  }
}
