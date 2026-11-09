import Foundation

/// What the cat's brain shows at one moment: its state stack and what the body should do.
public struct CatBrainFrame: Hashable, Sendable {
  public var stack: CatBrainStack
  /// The clip to play once the body is at `target`.
  public var action: CatAction
  public var target: CatTarget
  public var gaze: CatGaze
  /// How fast to travel, 0 walking to 1 running.
  public var pace: Double
  public var stepStart: Double
  public var stepEnd: Double
  /// Whether it would bat at a finger resting near the edge of the screen.
  public var eager: Bool
  /// How fast its clips play and it moves, and how big its small movements are, against 1.
  public var tempo: Double
  public var amplitude: Double
  /// How far it keeps from a finger, from 0 (right up to it) to 1 (well back).
  public var personalSpace: Double
  public var tricks: Set<CatLearnedTrick>
  public var feeling: CatFeeling
  /// The sound it makes as the step starts, if any, and how often again while the step lasts.
  public var voice: CatVoice?
  public var voiceEvery: Double?
  /// Whether it purrs: content and close, or kneading, rolling or blinking at you.
  public var purring: Bool

  public init(
    stack: CatBrainStack, action: CatAction, target: CatTarget, gaze: CatGaze, pace: Double,
    stepStart: Double, stepEnd: Double, eager: Bool = false, tempo: Double = 1,
    amplitude: Double = 1, personalSpace: Double = 0.3, tricks: Set<CatLearnedTrick> = [],
    feeling: CatFeeling = .content, voice: CatVoice? = nil, voiceEvery: Double? = nil,
    purring: Bool = false
  ) {
    self.stack = stack
    self.action = action
    self.target = target
    self.gaze = gaze
    self.pace = pace
    self.stepStart = stepStart
    self.stepEnd = stepEnd
    self.eager = eager
    self.tempo = tempo
    self.amplitude = amplitude
    self.personalSpace = personalSpace
    self.tricks = tricks
    self.feeling = feeling
    self.voice = voice
    self.voiceEvery = voiceEvery
    self.purring = purring
  }

  /// The still picture a surface without a scene shows for this frame.
  public var pose: PetPose { stack.vitality == .asleep ? .sleeping : .proud }
}
