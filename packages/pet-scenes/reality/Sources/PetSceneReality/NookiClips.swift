import Foundation
import RealityKit

/// Mochi's clips, which share one timeline in `Cat.usdz` and are played by trimming it.
///
/// Ear twitches, the bell, blinks and whether the eyes are open all live in the clips. The bind
/// pose has its eyes shut, so a clip starts as soon as the model loads. Clips stay in place: travel
/// comes from the room.
enum NookiClip: String, CaseIterable, Sendable {
  case idle
  case walk
  case sit
  case sleep
  case crouchWiggle
  case pounce

  /// Whether Mochi walks with the rig. When false it travels with the toy hop instead, and the
  /// rig keeps everything else.
  static let walksWithRig = true

  /// How fast the walk clip's feet travel at normal rate, in metres a second in the room.
  static let walkingSpeed: Float = 0.083 * NookiDiorama.mochiScale

  private static let fastestWalk: Float = 3

  var trim: ClosedRange<Double> {
    switch self {
    case .idle: 0...4
    case .walk: 4.333...5.333
    case .sit: 5.667...9.667
    case .sleep: 10...16
    case .crouchWiggle: 16.333...17.333
    case .pounce: 17.667...19.167
    }
  }

  var loops: Bool { self != .pounce }

  /// The playback rate that keeps feet from sliding at `speed` metres a second.
  static func walkRate(forTravelAt speed: Float) -> Float {
    min(max(speed / walkingSpeed, 1), fastestWalk)
  }

  /// Which clip a moment of the scene calls for.
  static func choose(frame: NookiFrame, yarn: NookiYarnPlay.Phase, walks: Bool = walksWithRig)
    -> NookiClip
  {
    switch yarn {
    case .watching, .proud:
      return .sit
    case .crouching, .wiggling:
      return .crouchWiggle
    case .chasing, .returning:
      return walks ? .walk : .idle
    case .pouncing:
      return .pounce
    case .resting:
      if frame.walk > 0, frame.walk < 1 { return walks ? .walk : .idle }
      if !frame.eyesOpen { return .sleep }
      return frame.wake >= 0.5 ? .idle : .sit
    }
  }
}

/// Plays Mochi's clips on the loaded model, blending from one to the next.
@MainActor final class NookiCatAnimator {
  static let blendLength: TimeInterval = 0.25

  private let player: Entity
  private var clips: [NookiClip: AnimationResource] = [:]
  private var controller: AnimationPlaybackController?
  private(set) var current: NookiClip?

  /// Nil for a model with no timeline to trim.
  init?(model: Entity) {
    guard let player = Self.firstAnimated(in: model),
      let timeline = player.availableAnimations.map(\.definition)
        .max(by: { $0.duration < $1.duration })
    else { return nil }
    self.player = player
    for clip in NookiClip.allCases {
      let view = AnimationView(
        source: timeline,
        name: clip.rawValue,
        repeatMode: clip.loops ? .repeat : .none,
        fillMode: .forwards,
        trimStart: clip.trim.lowerBound,
        trimEnd: clip.trim.upperBound)
      clips[clip] = try? AnimationResource.generate(with: view)
    }
    guard clips.count == NookiClip.allCases.count else { return nil }
  }

  /// Moves to `clip` at `rate`. Asking again for the clip already playing only changes the rate.
  func play(_ clip: NookiClip, rate: Float = 1, blend: TimeInterval = blendLength) {
    if clip == current {
      controller?.speed = rate
      return
    }
    guard let resource = clips[clip] else { return }
    current = clip
    let next = player.playAnimation(resource, transitionDuration: blend, startsPaused: false)
    next.speed = rate
    controller = next
  }

  var isPlaying: Bool { controller?.isPlaying == true }

  /// How long the clip has been trimmed to, or infinity for one that repeats.
  func duration(of clip: NookiClip) -> TimeInterval? {
    clips[clip]?.definition.duration
  }

  private static func firstAnimated(in entity: Entity) -> Entity? {
    if !entity.availableAnimations.isEmpty { return entity }
    return entity.children.lazy.compactMap(firstAnimated).first
  }
}
