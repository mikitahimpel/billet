import Testing

@testable import Design

@Suite struct MotionTests {
  @Test func quickIsShorterThanStandard() {
    #expect(0 < Motion.quick && Motion.quick < Motion.standard)
  }

  @Test(arguments: [
    (0, 2, Motion.Direction.forward),
    (3, 1, .backward),
    (1, 1, .still),
  ])
  func directionFollowsTheOrder(old: Int, new: Int, direction: Motion.Direction) {
    #expect(Motion.Direction(from: old, to: new) == direction)
  }

  @Test func aPageComesInFromTheSideItLiesOn() {
    #expect(Motion.entryOffset(.forward, reduceMotion: false) == Motion.shift)
    #expect(Motion.entryOffset(.backward, reduceMotion: false) == -Motion.shift)
    #expect(Motion.entryOffset(.still, reduceMotion: false) == 0)
  }

  @Test(arguments: [Motion.Direction.forward, .backward, .still])
  func reduceMotionOnlyFades(direction: Motion.Direction) {
    #expect(Motion.entryOffset(direction, reduceMotion: true) == 0)
  }
}
