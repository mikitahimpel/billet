import Foundation

/// A walk through the owner's chart for Labs and demo recordings: each stop is a brain stack
/// held for a few seconds and played through the same ``NookiCatScript`` as the brain, so it
/// shows what each state looks like in the room. It never changes the brain.
public struct CatMindTour: Sendable {
  public struct Stop: Hashable, Sendable {
    public var stack: CatBrainStack
    public var target: CatTarget
    public var gaze: CatGaze
    public var seconds: Double
    /// A stroke from whoever holds the phone as this stop starts.
    public var pet: Bool

    public init(
      _ step: CatActivityStep, vitality: CatVitality = .awake, target: CatTarget = .stay,
      gaze: CatGaze = .ahead, seconds: Double, pet: Bool = false
    ) {
      stack = CatBrainStack(
        vitality: vitality, step: step, interaction: pet ? .petted(.head) : nil)
      self.target = target
      self.gaze = gaze
      self.seconds = seconds
      self.pet = pet
    }
  }

  /// Idle at home, off to the cat tree, a game at the ball, a wash, home to loaf, a nap, a pet
  /// that she sleeps through, and back to her nap: about 90 seconds.
  public static let standard = CatMindTour(stops: [
    Stop(.sit, target: .home, gaze: .camera, seconds: 8),
    Stop(.inspectFurniture, target: .affordance(.shelf), seconds: 14),
    Stop(.batObject, target: .affordance(.toy), seconds: 14),
    Stop(.groomPaw, seconds: 8),
    Stop(.loaf, vitality: .drowsy, target: .home, seconds: 24),
    Stop(.curl, vitality: .asleep, target: .home, seconds: 10),
    Stop(.curl, vitality: .asleep, target: .home, seconds: 4, pet: true),
    Stop(.curl, vitality: .asleep, target: .home, seconds: 8),
  ])

  public let stops: [Stop]

  public init(stops: [Stop]) {
    self.stops = stops
  }

  public var seconds: Double { stops.reduce(0) { $0 + $1.seconds } }

  /// The stop at `elapsed` seconds into the tour with when it started, or nil once it is over.
  public func stop(at elapsed: Double) -> (stop: Stop, start: Double)? {
    var start = 0.0
    for stop in stops {
      if elapsed < start + stop.seconds { return (stop, start) }
      start += stop.seconds
    }
    return nil
  }

  /// The brain frame for `stop`, as if the brain had chosen it at `start`.
  public static func frame(_ stop: Stop, start: Double) -> CatBrainFrame {
    CatBrainFrame(
      stack: stop.stack, action: CatStatechart.clip(stop.stack.step), target: stop.target,
      gaze: stop.gaze, pace: CatStatechart.pace(stop.stack.step), stepStart: start,
      stepEnd: start + stop.seconds)
  }
}
