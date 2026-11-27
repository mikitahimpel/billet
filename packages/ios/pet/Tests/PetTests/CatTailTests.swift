import Testing

@testable import Pet

@Suite struct CatTailTests {
  private func run(
    _ tail: inout CatTail, seconds: Double, _ context: CatTail.Context
  ) -> CatTailCarriage {
    var t = 0.0
    while t < seconds {
      tail.advance(by: 1.0 / 30, context)
      t += 1.0 / 30
    }
    return tail.carriage
  }

  @Test(arguments: [
    (CatTail.Context(), CatTailMood.easy),
    (.init(source: .touch), .greeting),
    (.init(source: .partner), .greeting),
    (.init(source: .viewer, arousal: 0.3), .easy),
    (.init(source: .viewer, arousal: 0.7), .greeting),
    (.init(source: .viewer, arousal: 0.3, moving: true), .easy),
    (.init(source: .viewer, arousal: 0.3, moving: true, ahead: true), .greeting),
    (.init(source: .viewer, arousal: 0.3, ahead: true), .easy),
    (.init(source: .viewer, arousal: 0.7, moving: true), .easy),
    (.init(source: .viewer, arousal: 0.7, contentment: 0.1), .easy),
    (.init(source: .place("bowl"), stillness: 0.8), .intent),
    (.init(source: .place("bowl"), stillness: 0.2), .easy),
    (.init(source: .noise, stillness: 0.8), .intent),
    (.init(source: .sound, stillness: 0.8), .intent),
    (.init(source: .destination, stillness: 0.8), .easy),
    (.init(source: .nothing, stillness: 0.8), .easy),
    (.init(source: .touch, drowse: 0.7), .drowsy),
    (.init(drowse: 0.7), .drowsy),
  ])
  func theMomentAsksForAMood(_ context: CatTail.Context, _ mood: CatTailMood) {
    #expect(CatTail.asked(context) == mood)
  }

  @Test func leftAloneTheTailStaysAsHerPostureHasIt() {
    var tail = CatTail()
    #expect(run(&tail, seconds: 10, .init()) == .easy)
  }

  @Test func aGreetingBringsTheTailUpFastWithATrembleThatDies() {
    var tail = CatTail()
    let early = run(&tail, seconds: 0.5, .init(source: .partner))
    #expect(early.raise > 0.7)
    #expect(early.quiver > 0.4)
    let later = run(&tail, seconds: 2, .init(source: .partner))
    #expect(later.raise > 0.98)
    #expect(later.hook > 0.6)
    #expect(later.quiver == 0)
  }

  @Test func aGreetingOutlastsTheLookAndThenComesDownSlowerThanItRose() {
    var tail = CatTail()
    _ = run(&tail, seconds: 2, .init(source: .partner))
    _ = run(&tail, seconds: CatTail.greetingLinger - 0.2, .init())
    #expect(tail.mood == .greeting)
    #expect(tail.carriage.raise > 0.98)
    let falling = run(&tail, seconds: 0.7, .init())
    #expect(tail.mood == .easy)
    #expect(falling.raise > 0.4)
    #expect(run(&tail, seconds: 6, .init()).raise < 0.01)
  }

  @Test func aSecondGreetingWithinTheLingerDoesNotTrembleAgain() {
    var tail = CatTail()
    _ = run(&tail, seconds: 2, .init(source: .partner))
    _ = run(&tail, seconds: 1, .init())
    #expect(run(&tail, seconds: 0.2, .init(source: .touch)).quiver == 0)
  }

  @Test func staringTheTailGoesLowAndNearlyStill() {
    var tail = CatTail()
    let held = run(&tail, seconds: 4, .init(source: .place("window"), stillness: 0.9))
    #expect(tail.mood == .intent)
    #expect(held.raise < -0.45)
    #expect(held.swing < 0.2)
  }

  @Test func fallingAsleepEndsAGreetingAtOnce() {
    var tail = CatTail()
    _ = run(&tail, seconds: 2, .init(source: .partner))
    tail.advance(by: 1.0 / 30, .init(drowse: 0.8))
    #expect(tail.mood == .drowsy)
  }

  @Test func theTailNeverLeavesItsRange() {
    var tail = CatTail()
    let contexts: [CatTail.Context] = [
      .init(source: .partner), .init(source: .place("x"), stillness: 1), .init(drowse: 1), .init(),
    ]
    for step in 0..<3000 {
      let c = tail.advance(by: 0.05, contexts[(step / 37) % contexts.count])
      #expect((-1...1).contains(c.raise))
      #expect((0...1).contains(c.hook))
      #expect((0...1).contains(c.quiver))
      #expect(c.swing > 0 && c.pace > 0)
    }
  }
}
